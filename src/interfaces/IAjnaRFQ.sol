// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IAjnaRFQ {
    error NotAuthorized();
    error InvalidPrice();
    error InvalidIndex();
    error InvalidAmount();
    error InvalidMsgValue();
    error InvalidFee();
    error FillExpired();
    error OrderExpired();
    error OrderAlreadyFilled();
    error OrderCancelled();
    error InvalidSignature();
    error MissingLP();
    error FillAmountTooLowForMaker();
    error FillAmountTooLowForTaker();
    error InvalidLPBalance();

    event ApprovedOrder(bytes32 indexed hash);
    event CancelledOrder(bytes32 indexed hash);
    event FilledOrder(bytes32 indexed hash, address indexed taker, Order order, uint256 lpAmount, uint256 quoteAmount);

    struct Order {
        bool lpOrder;
        address maker;
        address taker;
        address pool;
        uint256 index;
        uint256 makeAmount;
        uint256 minMakeAmount;
        uint256 expiry;
        uint256 price;
    }

    function ORDER_TYPEHASH() external view returns (bytes32);

    function fee() external view returns (uint256);

    function approveOrder(Order memory order_) external returns (bytes32 hash);

    function approveOrder(bytes32 hash_) external;

    function cancelOrder(bytes32 hash_) external;

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
        returns (uint256 lpAmount, uint256 quoteAmount);
}
