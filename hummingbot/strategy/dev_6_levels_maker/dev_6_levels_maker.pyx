# distutils: language=c++
from decimal import Decimal
from libc.stdint cimport int64_t
import logging
from typing import (
    List,
    Tuple,
    Optional,
    Dict
)

from hummingbot.core.clock cimport Clock
from hummingbot.logger import HummingbotLogger
from hummingbot.core.data_type.limit_order cimport LimitOrder
from hummingbot.core.data_type.limit_order import LimitOrder
from hummingbot.core.data_type.order_book cimport OrderBook
from hummingbot.core.network_iterator import NetworkStatus
from hummingbot.connector.exchange_base import ExchangeBase
from hummingbot.connector.exchange_base cimport ExchangeBase
from hummingbot.core.event.events import OrderType
from hummingbot.core.event.events import PriceType

from hummingbot.strategy.market_trading_pair_tuple import MarketTradingPairTuple
from hummingbot.strategy.strategy_base import StrategyBase


s_decimal_NaN = Decimal("nan")
s_decimal_zero = Decimal(0)
pt_logger = None


cdef class LevelsMakerStrategy(StrategyBase):
    OPTION_LOG_NULL_ORDER_SIZE = 1 << 0
    OPTION_LOG_REMOVING_ORDER = 1 << 1
    OPTION_LOG_ADJUST_ORDER = 1 << 2
    OPTION_LOG_CREATE_ORDER = 1 << 3
    OPTION_LOG_MAKER_ORDER_FILLED = 1 << 4
    OPTION_LOG_STATUS_REPORT = 1 << 5
    OPTION_LOG_MAKER_ORDER_HEDGED = 1 << 6
    OPTION_LOG_ALL = 0x7fffffffffffffff
    CANCEL_EXPIRY_DURATION = 60.0

    @classmethod
    def logger(cls) -> HummingbotLogger:
        global pt_logger
        if pt_logger is None:
            pt_logger = logging.getLogger(__name__)
        return pt_logger

    def __init__(self,
                 market_infos: List[MarketTradingPairTuple],
                 order_type: str = "limit",
                 order_price: Optional[Decimal] = None,
                 is_buy: bool = True,
                 order_amount: Decimal = Decimal(1),
                 logging_options: int = OPTION_LOG_ALL,
                 status_report_interval: float = 900,
                 # levels: list = [],
                 level_01: Decimal = Decimal("1.0"),
                 level_02: Decimal = Decimal("1.0"),
                 level_03: Decimal = Decimal("1.0")):

        if len(market_infos) < 1:
            raise ValueError(f"market_infos must not be empty.")

        super().__init__()
        self._market_infos = {
            (market_info.market, market_info.trading_pair): market_info
            for market_info in market_infos
        }
        self._all_markets_ready = False
        self._place_orders = True
        self._logging_options = logging_options
        self._status_report_interval = status_report_interval
        self._order_type = order_type
        self._is_buy = is_buy
        self._order_amount = Decimal(order_amount)
        self._order_price = s_decimal_NaN if order_price is None else Decimal(order_price)
        self._level_01 = level_01
        self._level_02 = level_02
        self._level_03 = level_03
        self._active_level = 0,
        self._open_position = False,
        self._levels = []

        cdef:
            set all_markets = set([market_info.market for market_info in market_infos])

        self.c_add_markets(list(all_markets))

    @property
    def active_bids(self) -> List[Tuple[ExchangeBase, LimitOrder]]:
        return self._sb_order_tracker.active_bids

    @property
    def active_asks(self) -> List[Tuple[ExchangeBase, LimitOrder]]:
        return self._sb_order_tracker.active_asks

    @property
    def active_limit_orders(self) -> List[Tuple[ExchangeBase, LimitOrder]]:
        return self._sb_order_tracker.active_limit_orders

    @property
    def in_flight_cancels(self) -> Dict[str, float]:
        return self._sb_order_tracker.in_flight_cancels

    @property
    def market_info_to_active_orders(self) -> Dict[MarketTradingPairTuple, List[LimitOrder]]:
        return self._sb_order_tracker.market_pair_to_active_orders

    @property
    def logging_options(self) -> int:
        return self._logging_options

    @logging_options.setter
    def logging_options(self, int64_t logging_options):
        self._logging_options = logging_options

    @property
    def place_orders(self):
        return self._place_orders

    @property
    def format_status(self) -> str:
        cdef:
            list lines = []
            list warning_lines = []
            dict market_info_to_active_orders = self.market_info_to_active_orders
            list active_orders = []

        for market_info in self._market_infos.values():
            active_orders = self.market_info_to_active_orders.get(market_info, [])

            warning_lines.extend(self.network_warning([market_info]))

            markets_df = self.market_status_data_frame([market_info])
            lines.extend(["", "  Markets:"] + ["    " + line for line in str(markets_df).split("\n")])

            assets_df = self.wallet_balance_data_frame([market_info])
            lines.extend(["", "  Assets:"] + ["    " + line for line in str(assets_df).split("\n")])

            # See if there're any open orders.
            if len(active_orders) > 0:
                df = LimitOrder.to_pandas(active_orders)
                df_lines = str(df).split("\n")
                lines.extend(["", "  Active orders:"] +
                             ["    " + line for line in df_lines])
            else:
                lines.extend(["", "  No active maker orders."])

            warning_lines.extend(self.balance_warning([market_info]))

        if len(warning_lines) > 0:
            lines.extend(["", "*** WARNINGS ***"] + warning_lines)

        return "\n".join(lines)

    cdef c_start(self, Clock clock, double timestamp):
        # Calculate secondary levels and insert
        # Select active level
        StrategyBase.c_start(self, clock, timestamp)
        # Calculate Levels
        self.c_fibonacci_retracement_levels()

    cdef c_tick(self, double timestamp):
        StrategyBase.c_tick(self, timestamp)
        cdef:
            bint should_report_warnings = self._logging_options & self.OPTION_LOG_STATUS_REPORT
            list active_maker_orders = self.active_limit_orders
            object market_info
            object price

        try:
            # If under firs level, doing nothing, Select active level.
            # If price over active level place stop limit, level 0.5 Max stoploss
            # If price rise next level. Rise stop loss, non in first, level.
            # price % stoploss-> cancel and open limit.  with a margin of 10% in price.
            # If take_profit( time, min) or (go even)
            # sell to go even ( fees)
            # if not open order or stop loss executed, update active level.
            # if expired order, sell market cancel orders, update active_level.
            # if price over level 3 wait to expire an sell. stop bot.
            # if down trend stop bot.
            # self._all_markets_ready = all([market.ready for market in self._sb_markets])
            # if self._all_markets_ready:123456
            # price = market_info.get_price_for_volume(True, self._order_amount).result_price
            # if levels[0]>=price:

            self.logger().warning(f"Ticker Price")
            if not self._all_markets_ready:
                self.logger().warning(f"All markets ready")
                for market_info in self._market_infos.values():
                    self.logger().warning(f"Pair "f"{market_info.trading_pair}")
                    self.logger().warning(f"PRE")

                    # price = market_info.market.c_get_price(True, self._is_buy)
                    price = market_info.get_price_for_volume(True, self._order_amount).result_price
                    self.logger().warning(f"POST")
                    self.logger().warning(f"Current Price: " f"{price}")
                    price = market_info.market.get_price_by_type(market_info.trading_pair, PriceType.MidPrice)
                    self.logger().warning(f"BestBid: " f"{price}")
                    self.logger().warning(f"Fibonnaci Retracement Levels" f"{self._levels}")
                    self.c_set_current_level(price)
                    self.logger().warning(f"Current Level" f"{self._active_level}")
            # self.logger().warning(f"Level 1: "
            #                    f"({self._level_01}")

            # if not self._all_markets_ready:
            #     self._all_markets_ready = all([market.ready for market in self._sb_markets])
            #     if not self._all_markets_ready:
            #         # Markets not ready yet. Don't do anything.
            #         if should_report_warnings:
            #             self.logger().warning(f"Markets are not ready. No market making trades are permitted.")
            #         return
            #
            # if should_report_warnings:
            #     if not all([market.network_status is NetworkStatus.CONNECTED for market in self._sb_markets]):
            #         self.logger().warning(f"WARNING: Some markets are not connected or are down at the moment. Market "
            #                               f"making may be dangerous when markets or networks are unstable.")
            #
            # for market_info in self._market_infos.values():
            #     self.c_process_market(market_info)
            return
        finally:
            return

    # cdef c_place_order(self, object market_info):
    #     cdef:
    #         ExchangeBase market = market_info.market
    #         object quantized_amount = market.c_quantize_order_amount(market_info.trading_pair, self._order_amount)
    #         object quantized_price
    #
    #     self.logger().info(f"Checking to see if the user has enough balance to place orders")
    #
    #     if self.c_has_enough_balance(market_info):
    #         if self._order_type == "market":
    #             if self._is_buy:
    #                 order_id = self.c_buy_with_specific_market(market_info,
    #                                                            amount=quantized_amount)
    #                 self.logger().info("Market buy order has been executed")
    #             else:
    #                 order_id = self.c_sell_with_specific_market(market_info,
    #                                                             amount=quantized_amount)
    #                 self.logger().info("Market sell order has been executed")
    #         else:
    #             quantized_price = market.c_quantize_order_price(market_info.trading_pair, self._order_price)
    #             if self._is_buy:
    #                 order_id = self.c_buy_with_specific_market(market_info,
    #                                                            amount=quantized_amount,
    #                                                            order_type=OrderType.LIMIT,
    #                                                            price=quantized_price)
    #                 self.logger().info("Limit buy order has been placed")
    #
    #             else:
    #                 order_id = self.c_sell_with_specific_market(market_info,
    #                                                             amount=quantized_amount,
    #                                                             order_type=OrderType.LIMIT,
    #                                                             price=quantized_price)
    #                 self.logger().info("Limit sell order has been placed")
    #
    #     else:
    #         self.logger().info(f"Not enough balance to run the strategy. Please check balances and try again.")
    #
    # cdef c_has_enough_balance(self, object market_info):
    #     cdef:
    #         ExchangeBase market = market_info.market
    #         object base_asset_balance = market.c_get_balance(market_info.base_asset)
    #         object quote_asset_balance = market.c_get_balance(market_info.quote_asset)
    #         OrderBook order_book = market_info.order_book
    #         object price = market_info.get_price_for_volume(True, self._order_amount).result_price
    #
    #     return quote_asset_balance >= self._order_amount * price if self._is_buy else base_asset_balance >= self._order_amount
    #
    # cdef c_process_market(self, object market_info):
    #     cdef:
    #         ExchangeBase maker_market = market_info.market
    #
    #     if self._place_orders:
    #         self._place_orders = False
    #         self.c_place_order(market_info)

    cdef c_fibonacci_retracement_levels(self):
        cdef:
            ratios = [0, 0.236, 0.382, 0.5, 0.618, 0.786, 1]

            # colors = ["black", "r", "g", "b", "cyan", "magenta", "yellow"]
            max_level = self._level_03
            min_level = self._level_01
        ratios.reverse()
        for ratio in ratios:
            if max_level > min_level:  # Uptrend
                self._levels.append(max_level - (max_level - min_level) * ratio)
            else:  # Downtrend
                self._levels.append(min_level + (max_level - min_level) * ratio)

    cdef c_set_current_level(self, object price):
        cdef:
            band = 0
        band = next(x for x, val in enumerate(self._levels) if val >= price)
        self._active_level = band if self._active_level != band else self._active_level
