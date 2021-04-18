from typing import (
    List,
    Tuple,
)

from hummingbot.strategy.market_trading_pair_tuple import MarketTradingPairTuple
from hummingbot.strategy.dev_6_levels_maker import LevelsMakerStrategy
from hummingbot.strategy.dev_6_levels_maker.dev_6_levels_maker_config_map import dev_6_levels_maker_config_map


def start(self):
    try:
        # Here I get the strategy config values at start.
        order_amount = dev_6_levels_maker_config_map.get("order_amount").value
        order_type = dev_6_levels_maker_config_map.get("order_type").value
        is_buy = dev_6_levels_maker_config_map.get("is_buy").value
        market = dev_6_levels_maker_config_map.get("market").value.lower()
        raw_market_trading_pair = dev_6_levels_maker_config_map.get("market_trading_pair_tuple").value
        order_price = None
        level_01 = dev_6_levels_maker_config_map.get("level_01").value
        # level_02 = dev_6_levels_maker_config_map.get("level_02").value
        level_03 = dev_6_levels_maker_config_map.get("level_03").value

        if order_type == "limit":
            order_price = dev_6_levels_maker_config_map.get("order_price").value

        # New values

        try:
            trading_pair: str = raw_market_trading_pair
            assets: Tuple[str, str] = self._initialize_market_assets(market, [trading_pair])[0]
        except ValueError as e:
            self._notify(str(e))
            return

        market_names: List[Tuple[str, List[str]]] = [(market, [trading_pair])]

        self._initialize_wallet(token_trading_pairs=list(set(assets)))
        self._initialize_markets(market_names)
        self.assets = set(assets)

        maker_data = [self.markets[market], trading_pair] + list(assets)
        self.market_trading_pair_tuples = [MarketTradingPairTuple(*maker_data)]

        strategy_logging_options = LevelsMakerStrategy.OPTION_LOG_ALL

        # Invoke the strategy object
        self.strategy = LevelsMakerStrategy(market_infos=[MarketTradingPairTuple(*maker_data)],
                                            order_type=order_type,
                                            order_price=order_price,
                                            is_buy=is_buy,
                                            order_amount=order_amount,
                                            logging_options=strategy_logging_options,
                                            level_01=level_01,
                                            level_02=level_03,
                                            level_03=level_03)
    except Exception as e:
        self._notify(str(e))
        self.logger().error("Unknown error during initialization.", exc_info=True)
