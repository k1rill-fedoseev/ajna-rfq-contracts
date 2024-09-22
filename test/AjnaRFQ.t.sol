// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AjnaRFQ} from "../src/AjnaRFQ.sol";
import {IAjnaRFQ} from "../src/interfaces/IAjnaRFQ.sol";
import {IPool} from "../src/interfaces/IPool.sol";

import {AjnaPoolMock, WETH9} from "./Mocks.sol";

contract AjnaRFQTest is Test {
    AjnaRFQ public rfq;
    IERC20 public quote;
    AjnaPoolMock public pool;

    address maker;
    uint256 makerKey;
    address taker;

    function setUp() public {
        rfq = new AjnaRFQ(address(this), 0.2 ether);
        quote = IERC20(address(deployMockERC20("Quote", "Q", 18)));
        pool = new AjnaPoolMock(address(quote));

        (maker, makerKey) = makeAddrAndKey("maker");
        taker = makeAddr("taker");

        pool.setBucketExchangeRate(1234, 2 ether);
    }

    function testHashOrder() public {
        IAjnaRFQ.Order memory order = _makeOrder(true);
        bytes32 hash = rfq.hashOrder(order);
        bytes32 correctHash = keccak256(
            abi.encode(
                rfq.ORDER_TYPEHASH(),
                true,
                maker,
                taker,
                address(pool),
                1234,
                5 ether,
                0.5 ether,
                block.timestamp + 1 hours,
                0.9 ether
            )
        );

        assertEq(hash, correctHash);
    }

    function testApproveOrder() public {
        IAjnaRFQ.Order memory order = _makeOrder(true);

        vm.expectRevert(IAjnaRFQ.NotAuthorized.selector);
        rfq.approveOrder(order);

        vm.prank(maker);
        bytes32 hash = rfq.approveOrder(order);
        bytes32 hash2 = keccak256(abi.encodePacked("hash"));

        assertEq(rfq.approvedOrders(order.maker, hash), true);
        assertEq(rfq.approvedOrders(order.taker, hash), false);
        assertEq(rfq.approvedOrders(order.maker, hash2), false);

        vm.prank(maker);
        rfq.approveOrder(hash2);

        assertEq(rfq.approvedOrders(order.maker, hash2), true);
    }

    function testShortSignature() public {
        IAjnaRFQ.Order memory order = _makeOrder(true);
        bytes32 hash = rfq.hashOrder(order);
        bytes memory signature = _compactSig(_signOrder(hash));

        vm.prank(taker);
        rfq.fillOrder(order, signature, taker, order.index, 10 ether, 1 ether, block.timestamp);

        assertEq(rfq.filledAmounts(maker, hash), 5 ether);
    }

    function testERC1271Signature() public {
        IAjnaRFQ.Order memory order = _makeOrder(true);
        bytes32 hash = rfq.hashOrder(order);
        vm.mockCall(
            maker,
            abi.encodeCall(IERC1271.isValidSignature, (_typedHash(hash), "sig")),
            abi.encode(IERC1271.isValidSignature.selector)
        );

        vm.prank(taker);
        rfq.fillOrder(order, "sig", taker, order.index, 10 ether, 1 ether, block.timestamp);

        assertEq(rfq.filledAmounts(maker, hash), 5 ether);
    }

    function testPreApproveOrder() public {
        IAjnaRFQ.Order memory order = _makeOrder(true);
        bytes32 hash = rfq.hashOrder(order);

        vm.prank(maker);
        rfq.approveOrder(order);

        vm.prank(taker);
        rfq.fillOrder(order, "", taker, order.index, 10 ether, 1 ether, block.timestamp);

        assertEq(rfq.filledAmounts(maker, hash), 5 ether);
    }

    function testPreApproveOrderHash() public {
        IAjnaRFQ.Order memory order = _makeOrder(true);
        bytes32 hash = rfq.hashOrder(order);

        vm.prank(maker);
        rfq.approveOrder(hash);

        vm.prank(taker);
        rfq.fillOrder(order, "", taker, order.index, 10 ether, 1 ether, block.timestamp);

        assertEq(rfq.filledAmounts(maker, hash), 5 ether);
    }

    function testFullTake() public {
        IAjnaRFQ.Order memory order = _makeOrder(true);
        bytes32 hash = rfq.hashOrder(order);
        bytes memory signature = _signOrder(hash);

        vm.prank(taker);
        rfq.fillOrder(order, signature, taker, order.index, 10 ether, 1 ether, block.timestamp);

        assertEq(rfq.filledAmounts(maker, hash), 5 ether);
        assertEq(quote.balanceOf(maker), 9 ether);
        assertEq(quote.balanceOf(address(rfq)), 0.2 ether);
        assertEq(pool.lp(1234, taker), 5 ether);
    }

    function testPartialTake() public {
        IAjnaRFQ.Order memory order = _makeOrder(true);
        bytes32 hash = rfq.hashOrder(order);
        bytes memory signature = _signOrder(hash);

        vm.prank(taker);
        rfq.fillOrder(order, signature, taker, order.index, 8 ether, 1 ether, block.timestamp);

        assertEq(rfq.filledAmounts(maker, hash), 4.347826086956521739 ether);
        assertEq(quote.balanceOf(maker), 7.82608695652173913 ether);
        assertEq(quote.balanceOf(address(rfq)), 0.17391304347826087 ether);
        assertEq(pool.lp(1234, taker), 4.347826086956521739 ether);

        _approveLP(maker);

        vm.prank(taker);
        rfq.fillOrder(order, "", taker, order.index, 2 ether, 1 ether, block.timestamp);

        assertEq(rfq.filledAmounts(maker, hash), 5 ether);
        assertEq(quote.balanceOf(maker), 9 ether);
        assertEq(quote.balanceOf(address(rfq)), 0.200000000000000001 ether);
        assertEq(pool.lp(1234, taker), 5 ether);
    }

    function testCancelPartiallyFilledOrder() public {
        IAjnaRFQ.Order memory order = _makeOrder(true);
        bytes32 hash = rfq.hashOrder(order);
        bytes memory signature = _signOrder(hash);

        vm.prank(taker);
        rfq.fillOrder(order, signature, taker, order.index, 8 ether, 1 ether, block.timestamp);

        assertEq(rfq.filledAmounts(maker, hash), 4.347826086956521739 ether);

        vm.prank(maker);
        rfq.cancelOrder(hash);

        _approveLP(maker);

        vm.prank(taker);
        vm.expectRevert(IAjnaRFQ.OrderCancelled.selector);
        rfq.fillOrder(order, "", taker, order.index, 2 ether, 1 ether, block.timestamp);
    }

    function testNativeFills() public {
        quote = IERC20(address(new WETH9()));
        pool = new AjnaPoolMock(address(quote));
        pool.setBucketExchangeRate(1234, 2 ether);

        IAjnaRFQ.Order memory order = _makeOrder(true);
        bytes32 hash = rfq.hashOrder(order);
        bytes memory signature = _signOrder(hash);

        deal(taker, 10 ether);
        vm.prank(taker);
        rfq.fillOrder{value: 9 ether}(order, signature, taker, order.index, 8 ether, 1 ether, block.timestamp);

        assertEq(rfq.filledAmounts(maker, hash), 4.347826086956521739 ether);
        assertEq(quote.balanceOf(maker), 7.82608695652173913 ether);
        assertEq(quote.balanceOf(address(rfq)), 0.17391304347826087 ether);
        assertEq(pool.lp(1234, taker), 4.347826086956521739 ether);
        assertEq(taker.balance, 2 ether);

        _approveLP(maker);

        vm.prank(taker);
        rfq.fillOrder{value: 2 ether}(order, "", taker, order.index, 2 ether, 1 ether, block.timestamp);

        assertEq(rfq.filledAmounts(maker, hash), 5 ether);
        assertEq(quote.balanceOf(maker), 9 ether);
        assertEq(quote.balanceOf(address(rfq)), 0.200000000000000001 ether);
        assertEq(pool.lp(1234, taker), 5 ether);
        assertEq(taker.balance, 0.799999999999999999 ether);
    }

    function testFees() public {
        IAjnaRFQ.Order memory order = _makeOrder(true);
        bytes32 hash = rfq.hashOrder(order);
        bytes memory signature = _signOrder(hash);

        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, taker));
        rfq.updateFee(0.05 ether);

        vm.expectRevert(IAjnaRFQ.InvalidFee.selector);
        rfq.updateFee(0.25 ether);

        rfq.updateFee(0.05 ether);

        vm.prank(taker);
        rfq.fillOrder(order, signature, taker, order.index, 10 ether, 1 ether, block.timestamp);

        assertEq(rfq.filledAmounts(maker, hash), 5 ether);
        assertEq(quote.balanceOf(maker), 9 ether);
        assertEq(quote.balanceOf(address(rfq)), 0.05 ether);
        assertEq(pool.lp(1234, taker), 5 ether);

        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, taker));
        rfq.withdrawFee(address(quote));

        rfq.withdrawFee(address(quote));
        assertEq(quote.balanceOf(address(rfq)), 0);
        assertEq(quote.balanceOf(address(this)), 0.05 ether);
    }

    function testValidation() public {
        IAjnaRFQ.Order memory order = _makeOrder(true);
        bytes32 hash = rfq.hashOrder(order);
        bytes memory signature = _signOrder(hash);

        skip(2 hours);
        vm.prank(taker);
        vm.expectRevert(IAjnaRFQ.OrderExpired.selector);
        rfq.fillOrder(order, signature, taker, order.index, 10 ether, 1 ether, block.timestamp);
        rewind(2 hours);

        vm.prank(taker);
        vm.expectRevert(IAjnaRFQ.FillExpired.selector);
        rfq.fillOrder(order, signature, taker, order.index, 10 ether, 1 ether, block.timestamp - 1);

        vm.expectRevert(IAjnaRFQ.NotAuthorized.selector);
        rfq.fillOrder(order, signature, taker, order.index, 10 ether, 1 ether, block.timestamp);

        vm.prank(taker);
        vm.expectRevert(IAjnaRFQ.InvalidIndex.selector);
        rfq.fillOrder(order, signature, taker, 4321, 10 ether, 1 ether, block.timestamp);

        vm.prank(taker);
        vm.expectRevert(IAjnaRFQ.InvalidSignature.selector);
        rfq.fillOrder(order, hex"1234", taker, order.index, 10 ether, 1 ether, block.timestamp);

        pool.setLP(1234, maker, 0);
        vm.prank(taker);
        vm.expectRevert(IAjnaRFQ.MissingLP.selector);
        rfq.fillOrder(order, signature, taker, order.index, 10 ether, 1 ether, block.timestamp);
        pool.setLP(1234, maker, 6 ether);

        vm.prank(taker);
        vm.expectRevert(IAjnaRFQ.FillAmountTooLowForMaker.selector);
        rfq.fillOrder(order, signature, taker, order.index, 0.1 ether, 0.1 ether, block.timestamp);

        vm.prank(taker);
        vm.expectRevert(IAjnaRFQ.FillAmountTooLowForTaker.selector);
        rfq.fillOrder(order, signature, taker, order.index, 10 ether, 10 ether, block.timestamp);

        vm.prank(taker);
        rfq.fillOrder(order, signature, taker, order.index, 10 ether, 1 ether, block.timestamp);

        _approveLP(maker);
        vm.prank(taker);
        vm.expectRevert(IAjnaRFQ.OrderAlreadyFilled.selector);
        rfq.fillOrder(order, signature, taker, order.index, 10 ether, 1 ether, block.timestamp);
    }

    function testReverseFullTake() public {
        IAjnaRFQ.Order memory order = _makeOrder(false);
        bytes32 hash = rfq.hashOrder(order);
        bytes memory signature = _signOrder(hash);

        vm.prank(taker);
        rfq.fillOrder(order, signature, taker, order.index, 5 ether, 1 ether, block.timestamp);

        assertEq(rfq.filledAmounts(maker, hash), 9 ether);
        assertEq(quote.balanceOf(taker), 8.804347826086956521 ether);
        assertEq(quote.balanceOf(address(rfq)), 0.195652173913043479 ether);
        assertEq(pool.lp(1234, maker), 5 ether);
    }

    function testReversePartialTake() public {
        IAjnaRFQ.Order memory order = _makeOrder(false);
        bytes32 hash = rfq.hashOrder(order);
        bytes memory signature = _signOrder(hash);

        vm.prank(taker);
        rfq.fillOrder(order, signature, taker, order.index, 4 ether, 1 ether, block.timestamp);

        assertEq(rfq.filledAmounts(maker, hash), 7.2 ether);
        assertEq(quote.balanceOf(taker), 7.043478260869565217 ether);
        assertEq(quote.balanceOf(address(rfq)), 0.156521739130434783 ether);
        assertEq(pool.lp(1234, maker), 4 ether);

        _approveLP(taker);
        vm.prank(taker);
        rfq.fillOrder(order, "", taker, order.index, 2 ether, 1 ether, block.timestamp);

        assertEq(rfq.filledAmounts(maker, hash), 9 ether);
        assertEq(quote.balanceOf(taker), 8.804347826086956521 ether);
        assertEq(quote.balanceOf(address(rfq)), 0.195652173913043479 ether);
        assertEq(pool.lp(1234, maker), 5 ether);
    }

    function testZeroFeeTakes() public {
        rfq.updateFee(0);
        IAjnaRFQ.Order memory order = _makeOrder(true);
        bytes32 hash = rfq.hashOrder(order);
        bytes memory signature = _signOrder(hash);

        vm.prank(taker);
        rfq.fillOrder(order, signature, taker, order.index, 8 ether, 1 ether, block.timestamp);

        assertEq(rfq.filledAmounts(maker, hash), 4.444444444444444444 ether);
        assertEq(quote.balanceOf(maker), 8 ether);
        assertEq(quote.balanceOf(address(rfq)), 0);
        assertEq(pool.lp(1234, taker), 4.444444444444444444 ether);

        _approveLP(maker);

        vm.prank(taker);
        rfq.fillOrder(order, "", taker, order.index, 2 ether, 1 ether, block.timestamp);

        assertEq(rfq.filledAmounts(maker, hash), 5 ether);
        assertEq(quote.balanceOf(maker), 9.000000000000000001 ether);
        assertEq(quote.balanceOf(address(rfq)), 0);
        assertEq(pool.lp(1234, taker), 5 ether);
    }

    function testReverseZeroFeeTakes() public {
        rfq.updateFee(0);
        IAjnaRFQ.Order memory order = _makeOrder(false);
        bytes32 hash = rfq.hashOrder(order);
        bytes memory signature = _signOrder(hash);

        vm.prank(taker);
        rfq.fillOrder(order, signature, taker, order.index, 4 ether, 1 ether, block.timestamp);

        assertEq(rfq.filledAmounts(maker, hash), 7.2 ether);
        assertEq(quote.balanceOf(taker), 7.2 ether);
        assertEq(quote.balanceOf(address(rfq)), 0);
        assertEq(pool.lp(1234, maker), 4 ether);

        _approveLP(taker);
        vm.prank(taker);
        rfq.fillOrder(order, "", taker, order.index, 2 ether, 1 ether, block.timestamp);

        assertEq(rfq.filledAmounts(maker, hash), 9 ether);
        assertEq(quote.balanceOf(taker), 9 ether);
        assertEq(quote.balanceOf(address(rfq)), 0);
        assertEq(pool.lp(1234, maker), 5 ether);
    }

    function testNegPriceTakes() public {
        IAjnaRFQ.Order memory order = _makeOrder(true);
        order.price = 1.01 ether;
        bytes32 hash = rfq.hashOrder(order);
        bytes memory signature = _signOrder(hash);

        vm.prank(taker);
        rfq.fillOrder(order, signature, taker, order.index, 8 ether, 1 ether, block.timestamp);

        assertEq(rfq.filledAmounts(maker, hash), 3.960396039603960396 ether);
        assertEq(quote.balanceOf(maker), 8 ether);
        assertEq(quote.balanceOf(address(rfq)), 0);
        assertEq(pool.lp(1234, taker), 3.960396039603960396 ether);

        _approveLP(maker);

        vm.prank(taker);
        rfq.fillOrder(order, "", taker, order.index, 3 ether, 1 ether, block.timestamp);

        assertEq(rfq.filledAmounts(maker, hash), 5 ether);
        assertEq(quote.balanceOf(maker), 10.100000000000000001 ether);
        assertEq(quote.balanceOf(address(rfq)), 0);
        assertEq(pool.lp(1234, taker), 5 ether);
    }

    function testReverseNegPriceTakes() public {
        IAjnaRFQ.Order memory order = _makeOrder(false);
        order.price = 1.01 ether;
        bytes32 hash = rfq.hashOrder(order);
        bytes memory signature = _signOrder(hash);

        vm.prank(taker);
        rfq.fillOrder(order, signature, taker, order.index, 3 ether, 1 ether, block.timestamp);

        assertEq(rfq.filledAmounts(maker, hash), 6.06 ether);
        assertEq(quote.balanceOf(taker), 6.06 ether);
        assertEq(quote.balanceOf(address(rfq)), 0);
        assertEq(pool.lp(1234, maker), 3 ether);

        _approveLP(taker);
        vm.prank(taker);
        rfq.fillOrder(order, "", taker, order.index, 3 ether, 1 ether, block.timestamp);

        assertEq(rfq.filledAmounts(maker, hash), 9 ether);
        assertEq(quote.balanceOf(taker), 9 ether);
        assertEq(quote.balanceOf(address(rfq)), 0);
        assertEq(pool.lp(1234, maker), 4.455445544554455446 ether);
    }

    function testLowerDecimalTakes() public {
        quote = IERC20(address(deployMockERC20("Quote", "Q", 8)));
        pool = new AjnaPoolMock(address(quote));
        pool.setBucketExchangeRate(1234, 2 ether);

        IAjnaRFQ.Order memory order = _makeOrder(true);
        bytes32 hash = rfq.hashOrder(order);
        bytes memory signature = _signOrder(hash);

        vm.prank(taker);
        rfq.fillOrder(order, signature, taker, order.index, 8 ether, 1 ether, block.timestamp);

        assertEq(rfq.filledAmounts(maker, hash), 4.347826086956521739 ether);
        assertEq(quote.balanceOf(maker), 7.82608696 * 10 ** 8);
        assertEq(quote.balanceOf(address(rfq)), 0.17391304 * 10 ** 8);
        assertEq(pool.lp(1234, taker), 4.347826086956521739 ether);

        _approveLP(maker);

        vm.prank(taker);
        rfq.fillOrder(order, "", taker, order.index, 2 ether, 1 ether, block.timestamp);

        assertEq(rfq.filledAmounts(maker, hash), 5 ether);
        assertEq(quote.balanceOf(maker), 9.00000001 * 10 ** 8);
        assertEq(quote.balanceOf(address(rfq)), 0.2 * 10 ** 8);
        assertEq(pool.lp(1234, taker), 5 ether);
    }

    function testReverseLowerDecimalTakes() public {
        quote = IERC20(address(deployMockERC20("Quote", "Q", 8)));
        pool = new AjnaPoolMock(address(quote));
        pool.setBucketExchangeRate(1234, 2 ether);

        IAjnaRFQ.Order memory order = _makeOrder(false);
        bytes32 hash = rfq.hashOrder(order);
        bytes memory signature = _signOrder(hash);

        vm.prank(taker);
        rfq.fillOrder(order, signature, taker, order.index, 4 ether, 1 ether, block.timestamp);

        assertEq(rfq.filledAmounts(maker, hash), 7.2 ether);
        assertEq(quote.balanceOf(taker), 7.04347826 * 10 ** 8);
        assertEq(quote.balanceOf(address(rfq)), 0.15652174 * 10 ** 8);
        assertEq(pool.lp(1234, maker), 4 ether);

        _approveLP(taker);
        vm.prank(taker);
        rfq.fillOrder(order, "", taker, order.index, 2 ether, 1 ether, block.timestamp);

        assertEq(rfq.filledAmounts(maker, hash), 9 ether);
        assertEq(quote.balanceOf(taker), 8.80434782 * 10 ** 8);
        assertEq(quote.balanceOf(address(rfq)), 0.19565218 * 10 ** 8);
        assertEq(pool.lp(1234, maker), 5 ether);
    }

    function _makeOrder(bool lpOrder_) internal returns (IAjnaRFQ.Order memory) {
        if (lpOrder_) {
            pool.setLP(1234, maker, 6 ether);
            _approveLP(maker);
            deal(address(quote), taker, 11 * 10 ** IERC20Metadata(address(quote)).decimals());
            vm.prank(taker);
            quote.approve(address(rfq), type(uint256).max);
        } else {
            deal(address(quote), maker, 11 * 10 ** IERC20Metadata(address(quote)).decimals());
            vm.prank(maker);
            quote.approve(address(rfq), type(uint256).max);
            pool.setLP(1234, taker, 6 ether);
            _approveLP(taker);
        }
        return IAjnaRFQ.Order({
            lpOrder: lpOrder_,
            maker: maker,
            taker: taker,
            pool: address(pool),
            index: 1234,
            makeAmount: lpOrder_ ? 5 ether : 9 ether,
            minMakeAmount: lpOrder_ ? 0.5 ether : 1 ether,
            expiry: block.timestamp + 1 hours,
            price: 0.9 ether
        });
    }

    function _typedHash(bytes32 hash_) internal view returns (bytes32) {
        return MessageHashUtils.toTypedDataHash(rfq.DOMAIN_SEPARATOR(), hash_);
    }

    function _signOrder(bytes32 hash_) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(makerKey, _typedHash(hash_));
        return abi.encodePacked(r, s, v);
    }

    function _compactSig(bytes memory sig_) internal pure returns (bytes memory) {
        assembly {
            if gt(byte(31, mload(add(sig_, 65))), 27) { mstore(add(sig_, 64), add(mload(add(sig_, 64)), shl(255, 1))) }
            mstore(sig_, 64)
        }
        return sig_;
    }

    function _approveLP(address addr_) internal {
        uint256[] memory indices = new uint256[](1);
        indices[0] = 1234;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = type(uint256).max;
        address[] memory transferors = new address[](1);
        transferors[0] = address(rfq);
        vm.startPrank(addr_);
        pool.approveLPTransferors(transferors);
        pool.increaseLPAllowance(address(rfq), indices, amounts);
        vm.stopPrank();
    }
}
