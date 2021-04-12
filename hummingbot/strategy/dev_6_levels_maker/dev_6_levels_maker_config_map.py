from hummingbot.client.config.config_var import ConfigVar
from hummingbot.client.config.config_validators import (
    validate_exchange,
    validate_market_trading_pair,
    validate_decimal
)

from hummingbot.client.settings import (
    required_exchanges,
    EXAMPLE_PAIRS,
)

from decimal import Decimal

from typing import Optional


def trading_pair_prompt():
    market = dev_6_levels_maker_config_map.get("market").value
    example = EXAMPLE_PAIRS.get(market)
    return "Enter the token trading pair you would like to trade on %s%s >>> " \
           % (market, f" (e.g. {example})" if example else "")


def str2bool(value: str):
    return str(value).lower() in ("yes", "true", "t", "1")


# checks if the trading pair is valid
def validate_market_trading_pair_tuple(value: str) -> Optional[str]:
    market = dev_6_levels_maker_config_map.get("market").value
    return validate_market_trading_pair(market, value)


dev_6_levels_maker_config_map = {
    "strategy":
        ConfigVar(key="strategy",
                  prompt="",
                  default="dev_6_levels_maker"),
    "market":
        ConfigVar(key="market",
                  prompt="Enter the name of the exchange >>> ",
                  validator=validate_exchange,
                  on_validated=lambda value: required_exchanges.append(value)),
    "market_trading_pair_tuple":
        ConfigVar(key="market_trading_pair_tuple",
                  prompt=trading_pair_prompt,
                  validator=validate_market_trading_pair_tuple),
    "order_type":
        ConfigVar(key="order_type",
                  prompt="Enter type of order (limit/market) default is market >>> ",
                  type_str="str",
                  validator=lambda v: None if v in {"limit", "market", ""} else "Invalid order type.",
                  default="market"),
    "is_buy":
        ConfigVar(key="is_buy",
                  prompt="Enter True for Buy order and False for Sell order (default is Buy Order) >>> ",
                  type_str="bool",
                  default=True),
    "order_amount":
        ConfigVar(key="order_amount",
                  prompt="What is your preferred quantity per order in % of your balance "
                         "(denominated in the base asset, default is 3%) ? >>> ",
                  default=3.0,
                  type_str="decimal"),
    "max_stop_loss":
        ConfigVar(key="max_stop_loss",
                  prompt="What is your stop loss margin in  % of order amount "
                         "(denominated in the base asset, default is 3%) ? >>> ",
                  default=3.0,
                  type_str="decimal"),
    "take_profit":
        ConfigVar(key="take_profit",
                  prompt="What is your considered basic profit to take  "
                         "(denominated in the base asset, default is 3%) ? >>> ",
                  default=3.0,
                  type_str="decimal"),
    "order_price":
        ConfigVar(key="order_price",
                  prompt="What is the price of the limit order ? >>> ",
                  required_if=lambda: dev_6_levels_maker_config_map.get("order_type").value == "limit",
                  type_str="decimal"),
    "level_01":
        ConfigVar(key="level_01",
                  prompt="Intro level 1 of your band ? >>> ",
                  validator=lambda v: validate_decimal(v, Decimal(0), inclusive=False),
                  # required_if=lambda: dev_6_levels_maker_config_map.get("order_type").value == "limit",
                  type_str="decimal"),
    "level_02":
        ConfigVar(key="level_02",
                  prompt="Intro level 2 of your band ? >>> ",
                  validator=lambda v: validate_decimal(v, Decimal(0), inclusive=False),
                  # required_if=lambda: dev_6_levels_maker_config_map.get("order_type").value == "limit",
                  type_str="decimal"),
    "level_03":
        ConfigVar(key="level_03",
                  prompt="Intro level 3 Top of your band ? >>> ",
                  validator=lambda v: validate_decimal(v, Decimal(0), inclusive=False),
                  # required_if=lambda: dev_6_levels_maker_config_map.get("order_type").value == "limit",
                  type_str="decimal")
}
