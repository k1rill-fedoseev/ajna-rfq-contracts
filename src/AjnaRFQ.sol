// SPDX-License-Identifier: MIT

pragma solidity 0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {Multicall} from "@openzeppelin/contracts/utils/Multicall.sol";

import {IAjnaRFQ} from "./interfaces/IAjnaRFQ.sol";
import {IPool} from "./interfaces/IPool.sol";
import {IWETH} from "./interfaces/IWETH.sol";

contract AjnaRFQ is IAjnaRFQ, Ownable, Multicall, EIP712 {
    using SafeERC20 for IERC20;

    constructor(address owner_, uint256 fee_) Ownable(owner_) EIP712("Ajna RFQ", "1") {
        require(fee_ <= 1 ether, InvalidFee());
        fee = fee_;
    }

    // @dev keccak256("Order(bool lpOrder,address maker,address taker,address pool,uint256 index,uint256 makeAmount,uint256 minMakeAmount,uint256 expiry,uint256 price)")
    bytes32 public constant ORDER_TYPEHASH = 0xa01e31d465d9cadfa55d9056e9f9a52ee305fbbb68e06cf7c1dbcdc2897e3122;

    struct Vars {
        bytes32 hash;
        address token;
        uint256 scale;
        uint256 rate;
        uint256 filledAmount;
        address lpSender;
        address lpReceiver;
        address quoteSender;
        address quoteReceiver;
        uint256 oldLpBalance;
        uint256 newLpBalance;
        uint256 lp;
        uint256 rem;
        uint256 priceWithFee;
        uint256 lpAmount;
        uint256 quoteAmount;
        uint256 pullQuoteAmount;
        uint256 fillQuoteAmount;
    }

    // @dev Approved order hashes by maker address.
    mapping(address => mapping(bytes32 => bool)) public approvedOrders;
    // @dev Filled order amounts by maker address and order hash.
    mapping(address => mapping(bytes32 => uint256)) public filledAmounts;

    uint256 public fee;

    /* ========== Public Owner Functions ========== */

    /**
     * @dev Updates fee as a percentage of taker's profit.
     * Fee increases are not allowed.
     * Can be called only by the contract owner.
     * @param fee_ The updated fee value (100% = 1 ether).
     */
    function updateFee(uint256 fee_) external onlyOwner {
        require(fee_ < fee, InvalidFee());
        fee = fee_;
    }

    /**
     * @dev Withdraws accumulated fee in given quote token.
     * Can be called only by the contract owner.
     * @param token_ The quote token address to withdraw fees in.
     */
    function withdrawFee(address token_) external onlyOwner {
        IERC20(token_).safeTransfer(owner(), IERC20(token_).balanceOf(address(this)));
    }

    /* ========== Public User Functions ========== */

    /**
     * @notice Approves given order on behalf of the caller.
     * @dev Intended for use with non-EOA wallets that don't support ERC-1271.
     * Will revert if some basic order validation fails.
     * @param order_ The order struct to approve.
     * @return hash The approved order hash.
     */
    function approveOrder(Order memory order_) external returns (bytes32 hash) {
        require(msg.sender == order_.maker, NotAuthorized());
        require(order_.expiry >= block.timestamp, OrderExpired());
        require(order_.price <= 1.01 ether, InvalidPrice());

        hash = hashOrder(order_);

        approvedOrders[msg.sender][hash] = true;

        emit ApprovedOrder(hash);
    }

    /**
     * @notice Approves given order on behalf of the caller by its hash.
     * @dev Intended for use with non-EOA wallets that don't support ERC-1271.
     * @param hash_ The order hash to approve.
     */
    function approveOrder(bytes32 hash_) external {
        approvedOrders[msg.sender][hash_] = true;

        emit ApprovedOrder(hash_);
    }

    /**
     * @notice Cancels given order on behalf of the caller by its hash.
     * @dev Intended for cancelling active orders that are yet to be filled.
     * @param hash_ The order hash to cancel.
     */
    function cancelOrder(bytes32 hash_) external {
        filledAmounts[msg.sender][hash_] = type(uint256).max;

        emit CancelledOrder(hash_);
    }

    /**
     * @notice Fills order with caller acting as a taker.
     * @dev Will revert if some any order validation fails.
     * Partial fills are supported if allowed by both maker and taker, however maker approval will be reset,
     * so maker need to re-approve Ajna LP after each partial fill.
     * @param order_ The order struct to fill.
     * @param signature_ The order ECDSA or ERC-1271 signature. Ignored for already filled or pre-approved orders.
     * @param to_ Taker receiver address for sending Ajna LP to.
     * @param index_ Bucket index to take LP from.
     * @param fillAmount_ Max amount of quote token or LP taker is willing to spend.
     * @param minFillAmount_ Min amount of quote token or LP taker is willing to spend.
     * @param expiry_ Expiration deadline timestamp.
     */
    function fillOrder(
        Order memory order_,
        bytes memory signature_,
        address to_,
        uint256 index_,
        uint256 fillAmount_,
        uint256 minFillAmount_,
        uint256 expiry_
    )
        external
        payable
        returns (uint256, uint256)
    {
        require(expiry_ >= block.timestamp, FillExpired());
        require(order_.expiry >= block.timestamp, OrderExpired());
        require(order_.price <= 1.01 ether, InvalidPrice());
        require(order_.taker == address(0) || order_.taker == msg.sender, NotAuthorized());
        require(index_ == order_.index || !order_.lpOrder && index_ > order_.index, InvalidIndex());

        Vars memory vars;
        vars.hash = hashOrder(order_);
        vars.token = IPool(order_.pool).quoteTokenAddress();
        vars.scale = IPool(order_.pool).quoteTokenScale();
        vars.rate = IPool(order_.pool).bucketExchangeRate(index_);

        // validate signature/approval for new orders, revert if order is already filled/cancelled
        vars.filledAmount = filledAmounts[order_.maker][vars.hash];
        if (vars.filledAmount == 0) {
            if (
                !_isValidSignatureNow(order_.maker, _hashTypedDataV4(vars.hash), signature_)
                    && !approvedOrders[order_.maker][vars.hash]
            ) {
                revert InvalidSignature();
            }
        } else if (vars.filledAmount == type(uint256).max) {
            revert OrderCancelled();
        } else if (vars.filledAmount >= order_.makeAmount) {
            revert OrderAlreadyFilled();
        }

        if (order_.lpOrder) {
            vars.lpSender = order_.maker;
            vars.lpReceiver = to_;
            vars.quoteSender = msg.sender;
            vars.quoteReceiver = order_.maker;
        } else {
            vars.lpSender = msg.sender;
            vars.lpReceiver = order_.maker;
            vars.quoteSender = order_.maker;
            vars.quoteReceiver = to_;
        }

        uint256[] memory indexes = new uint256[](1);
        indexes[0] = index_;

        // transfer approved LP to RFQ contract
        (vars.oldLpBalance,) = IPool(order_.pool).lenderInfo(index_, address(this));
        IPool(order_.pool).transferLP(vars.lpSender, address(this), indexes);
        (vars.newLpBalance,) = IPool(order_.pool).lenderInfo(index_, address(this));

        vars.lp = vars.newLpBalance - vars.oldLpBalance;
        require(vars.lp > 0, MissingLP());

        vars.rem = order_.makeAmount - vars.filledAmount;
        vars.priceWithFee = order_.price;
        if (order_.price < 1 ether) {
            // apply proportional fee on profit only
            unchecked {
                vars.priceWithFee += _multiplyDown(1 ether - order_.price, fee);
            }
        }

        // fill amount in LP is min of available LP, remaining order LP and taker LP quote
        if (order_.lpOrder) {
            vars.lpAmount = _min(vars.lp, vars.rem);
            vars.quoteAmount = _multiplyUp(_multiplyUp(vars.lpAmount, vars.rate), vars.priceWithFee);
            if (vars.quoteAmount > fillAmount_) {
                vars.quoteAmount = fillAmount_;
                vars.lpAmount = _min(vars.lpAmount, _divideDown(_divideDown(fillAmount_, vars.priceWithFee), vars.rate));
            }
            vars.pullQuoteAmount = _scaleUp(vars.quoteAmount, vars.scale);
            vars.fillQuoteAmount = _scaleUp(vars.quoteAmount * order_.price / vars.priceWithFee, vars.scale);
            require(
                vars.lpAmount >= order_.minMakeAmount && vars.lpAmount > 0 && vars.fillQuoteAmount > 0,
                FillAmountTooLowForMaker()
            );
            require(vars.quoteAmount >= minFillAmount_ && vars.pullQuoteAmount > 0, FillAmountTooLowForTaker());

            filledAmounts[order_.maker][vars.hash] = vars.filledAmount + vars.lpAmount;
        } else {
            vars.rem = _min(
                vars.rem,
                _min(
                    IERC20(vars.token).allowance(vars.quoteSender, address(this)),
                    IERC20(vars.token).balanceOf(vars.quoteSender)
                ) * vars.scale
            );

            vars.lpAmount = _min(vars.lp, fillAmount_);
            vars.quoteAmount = _multiplyDown(_multiplyDown(vars.lpAmount, vars.rate), order_.price);
            if (vars.quoteAmount > vars.rem) {
                vars.quoteAmount = vars.rem;
                vars.lpAmount = _min(vars.lpAmount, _divideUp(_divideUp(vars.rem, order_.price), vars.rate));
            }
            vars.pullQuoteAmount = _scaleDown(vars.quoteAmount, vars.scale);
            vars.fillQuoteAmount = _scaleDown(vars.quoteAmount * order_.price / vars.priceWithFee, vars.scale);
            require(
                vars.lpAmount >= minFillAmount_ && vars.lpAmount > 0 && vars.fillQuoteAmount > 0,
                FillAmountTooLowForTaker()
            );
            require(vars.quoteAmount >= order_.minMakeAmount && vars.pullQuoteAmount > 0, FillAmountTooLowForMaker());

            filledAmounts[order_.maker][vars.hash] = vars.filledAmount + vars.quoteAmount;
        }

        // transfer approved quote token from quote sender to RFQ contract
        if (msg.value > 0) {
            require(order_.lpOrder && vars.scale == 1 && msg.value >= vars.pullQuoteAmount, InvalidMsgValue());
            IWETH(vars.token).deposit{value: vars.pullQuoteAmount}();
            if (msg.value > vars.pullQuoteAmount) {
                unchecked {
                    payable(msg.sender).transfer(msg.value - vars.pullQuoteAmount);
                }
            }
        } else {
            IERC20(vars.token).safeTransferFrom(vars.quoteSender, address(this), vars.pullQuoteAmount);
        }

        // fill order in quote token
        IERC20(vars.token).safeTransfer(vars.quoteReceiver, vars.fillQuoteAmount);

        // fill order in lp
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = vars.lpAmount;
        IPool(order_.pool).increaseLPAllowance(vars.lpReceiver, indexes, amounts);
        IPool(order_.pool).transferLP(address(this), vars.lpReceiver, indexes);

        // refund remaining LP
        if (vars.lpAmount < vars.lp) {
            unchecked {
                amounts[0] = vars.lp - vars.lpAmount;
            }
            IPool(order_.pool).increaseLPAllowance(vars.lpSender, indexes, amounts);
            IPool(order_.pool).transferLP(address(this), vars.lpSender, indexes);
        }

        // sanity check no LP is left
        (vars.newLpBalance,) = IPool(order_.pool).lenderInfo(index_, address(this));
        require(vars.newLpBalance == vars.oldLpBalance, InvalidLPBalance());

        emit FilledOrder(vars.hash, msg.sender, order_, vars.lpAmount, vars.quoteAmount);

        return (vars.lpAmount, vars.quoteAmount);
    }

    /* ========== Public View/Pure Functions ========== */

    /**
     * @notice Computes order hash from the order struct.
     * @param order_ The order struct to compute hash for.
     * @return The computed order hash.
     */
    function hashOrder(Order memory order_) public pure returns (bytes32) {
        return keccak256(abi.encode(ORDER_TYPEHASH, order_));
    }

    /**
     * @dev Returns the domain separator used in the encoding of the order, as defined by EIP-712.
     * @return Domain separator.
     */
    function DOMAIN_SEPARATOR() external view virtual returns (bytes32) {
        return _domainSeparatorV4();
    }

    /* ========== Internal View/Pure Functions ========== */

    function _isValidSignatureNow(address signer_, bytes32 hash_, bytes memory sig_) internal view returns (bool) {
        address recovered;
        ECDSA.RecoverError err;
        if (sig_.length == 64) {
            (bytes32 r, bytes32 vs) = abi.decode(sig_, (bytes32, bytes32));
            (recovered, err,) = ECDSA.tryRecover(hash_, r, vs);
        } else {
            (recovered, err,) = ECDSA.tryRecover(hash_, sig_);
        }
        return err == ECDSA.RecoverError.NoError && recovered == signer_
            || SignatureChecker.isValidERC1271SignatureNow(signer_, hash_, sig_);
    }

    function _min(uint256 a_, uint256 b_) internal pure returns (uint256) {
        if (a_ < b_) return a_;
        return b_;
    }

    function _multiplyDown(uint256 a_, uint256 b_) internal pure returns (uint256) {
        return a_ * b_ / 1 ether;
    }

    function _multiplyUp(uint256 a_, uint256 b_) internal pure returns (uint256) {
        return (a_ * b_ + 1 ether - 1) / 1 ether;
    }

    function _divideDown(uint256 a_, uint256 b_) internal pure returns (uint256) {
        return a_ * 1 ether / b_;
    }

    function _divideUp(uint256 a_, uint256 b_) internal pure returns (uint256) {
        return (a_ * 1 ether + b_ - 1) / b_;
    }

    function _scaleDown(uint256 a_, uint256 b_) internal pure returns (uint256) {
        return a_ / b_;
    }

    function _scaleUp(uint256 a_, uint256 b_) internal pure returns (uint256) {
        return (a_ + b_ - 1) / b_;
    }
}
