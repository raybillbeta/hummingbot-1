# distutils: language=c++

from hummingbot.strategy.strategy_base cimport StrategyBase
from libc.stdint cimport int64_t

cdef class LevelsMakerStrategy(StrategyBase):
    cdef:
        dict _market_infos
        bint _all_markets_ready
        bint _place_orders
        bint _is_buy
        str _order_type
        bint _open_position

        double _status_report_interval
        object _order_price
        object _order_amount
        list _levels
        object _level_01
        object _level_02
        object _level_03
        object _active_level
        dict _tracked_orders
        dict _order_id_to_market_info

        int64_t _logging_options

    # cdef c_process_market(self, object market_info)
    # cdef c_place_order(self, object market_info)
    # cdef c_has_enough_balance(self, object market_info)
    cdef c_fibonacci_retracement_levels(self)
    cdef c_set_current_level(self, object price)
    cdef c_first_situation(self, object price)
    cdef c_intermediate_situation(self, object price)
    cdef c_take_profit(self, object price)
    cdef c_expire_position(self, object price)
