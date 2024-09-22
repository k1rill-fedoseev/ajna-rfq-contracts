// SPDX-License-Identifier: MIT

pragma solidity 0.8.27;

import {IAjnaRFQ} from "../interfaces/IAjnaRFQ.sol";
import {IPool} from "../interfaces/IPool.sol";

contract AjnaRFQProxyActions {
    IAjnaRFQ public immutable rfq;

    constructor(IAjnaRFQ rfq_) {
        rfq = rfq_;
    }

    function approveRFQOrder(IAjnaRFQ.Order memory order_, bool approveTransferor_, bool approveBucket_) external {
        _approveRFQ(order_.pool, order_.index, approveTransferor_, approveBucket_);
        rfq.approveOrder(order_);
    }

    function approveBucket(address pool_, uint256 index_) external {
        _approveRFQ(pool_, index_, false, true);
    }

    function fillReverseRFQOrder(
        IAjnaRFQ.Order memory order_,
        bytes memory signature_,
        uint256 index_,
        bool approveTransferor_,
        bool approveBucket_,
        uint256 fillAmount_,
        uint256 minFillAmount_,
        uint256 expiry_
    )
        external
    {
        _approveRFQ(order_.pool, index_, approveTransferor_, approveBucket_);
        rfq.fillOrder(order_, signature_, msg.sender, index_, fillAmount_, minFillAmount_, expiry_);
    }

    function _approveRFQ(address pool_, uint256 index_, bool approveTransferor_, bool approveBucket_) internal {
        if (approveTransferor_) {
            address[] memory transferrors = new address[](1);
            transferrors[0] = address(rfq);
            IPool(pool_).approveLPTransferors(transferrors);
        }
        if (approveBucket_) {
            uint256[] memory indexes = new uint256[](1);
            uint256[] memory amounts = new uint256[](1);
            indexes[0] = index_;
            amounts[0] = type(uint256).max;
            IPool(pool_).increaseLPAllowance(address(rfq), indexes, amounts);
        }
    }
}
