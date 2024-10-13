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
        // @dev True, when maker sells LP for quote tokens, false for opposite.
        bool lpOrder;
        // @dev Address of the maker, LP and quote tokens for maker are sent to/from it, signature is validated against it too.
        address maker;
        // @dev Address of the taker allowed to fill order, zero address for no restrictions.
        address taker;
        // @dev Address of the Ajna ERC20 pool to sell/buy LP from. Quote token address is retrieved from here.
        address pool;
        // @dev For LP => quote orders, index of the sold LP Ajna bucket. For quote => LP orders, min bucket index that maker will accept.
        uint256 index;
        // @dev Total amount of LP or quote tokens maker is willing to sell.
        uint256 makeAmount;
        // @dev Min amount of LP or quote tokens maker is willing to sell. If less than makeAmount, partial fills will be allowed.
        uint256 minMakeAmount;
        // @dev Order expiration timestamp.
        uint256 expiry;
        // @dev LP price in quote tokens at which maker is selling/buying LP, as a percentage of 1e18. e.g. 0.99e18 means 1% discount to the primary market.
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
