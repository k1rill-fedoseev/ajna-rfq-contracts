// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AjnaRFQ} from "../src/AjnaRFQ.sol";
import {IAjnaRFQ} from "../src/interfaces/IAjnaRFQ.sol";
import {IPool} from "../src/interfaces/IPool.sol";

contract IntegrationTest is Test {
    AjnaRFQ public rfq;

    address internal constant user = 0xC75afc43dEDb449e741f8005D76D5FA880a1CeF9;
    address internal constant pool = 0x3BA6A019eD5541b5F5555d8593080042Cf3ae5f4;
    address internal constant weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    uint256 internal constant index = 4129;

    function setUp() public {
        vm.createSelectFork(vm.envOr(string("MAINNET_FORK_RPC_URL"), string("https://rpc.ankr.com/eth")), 20_851_555);

        rfq = new AjnaRFQ(address(this), 0.2 ether);

        deal(weth, address(this), 20 ether);

        vm.mockCall(address(1), "", abi.encode(user));
    }

    function testFill() public {
        IAjnaRFQ.Order memory order = IAjnaRFQ.Order({
            lpOrder: true,
            maker: user,
            taker: address(0),
            pool: pool,
            index: index,
            makeAmount: 10 ether,
            minMakeAmount: 0.5 ether,
            expiry: block.timestamp + 1 hours,
            price: 0.99 ether
        });

        vm.startPrank(user);

        address[] memory transferrors = new address[](1);
        uint256[] memory indexes = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        transferrors[0] = address(rfq);
        indexes[0] = index;
        amounts[0] = type(uint256).max;

        IPool(pool).approveLPTransferors(transferrors);
        IPool(pool).increaseLPAllowance(address(rfq), indexes, amounts);
        rfq.approveOrder(order);

        vm.stopPrank();

        IPool(pool).approveLPTransferors(transferrors);
        IERC20(weth).approve(address(rfq), type(uint256).max);

        (uint256 lp,) = IPool(pool).lenderInfo(index, user);
        assertEq(lp, 39.965028801848761892 ether);
        (lp,) = IPool(pool).lenderInfo(index, address(this));
        assertEq(lp, 0);

        (uint256 quoteAmount, uint256 lpAmount) =
            rfq.fillOrder(order, "", address(this), index, 2 ether, 1 ether, block.timestamp + 1 hours);

        vm.prank(user);
        IPool(pool).increaseLPAllowance(address(rfq), indexes, amounts);

        (quoteAmount, lpAmount) =
            rfq.fillOrder(order, "", address(this), index, 2 ether, 0.5 ether, block.timestamp + 1 hours);

        assertEq(IERC20(weth).balanceOf(address(this)), 16 ether);
        assertEq(IERC20(weth).balanceOf(user), 3.99193548387096774 ether);
        assertEq(IERC20(weth).balanceOf(address(rfq)), 0.00806451612903226 ether);
        (lp,) = IPool(pool).lenderInfo(index, user);
        assertEq(lp, 35.986551102930546056 ether);
        (lp,) = IPool(pool).lenderInfo(index, address(this));
        assertEq(lp, 3.978477698918215836 ether);
    }

    function testReverseFill() public {
        IAjnaRFQ.Order memory order = IAjnaRFQ.Order({
            lpOrder: false,
            maker: address(this),
            taker: address(0),
            pool: pool,
            index: index,
            makeAmount: 10 ether,
            minMakeAmount: 0.5 ether,
            expiry: block.timestamp + 1 hours,
            price: 0.99 ether
        });

        address[] memory transferrors = new address[](1);
        uint256[] memory indexes = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        transferrors[0] = address(rfq);
        indexes[0] = index;
        amounts[0] = type(uint256).max;

        rfq.approveOrder(order);
        IPool(pool).approveLPTransferors(transferrors);
        IERC20(weth).approve(address(rfq), type(uint256).max);

        vm.startPrank(user);
        IPool(pool).approveLPTransferors(transferrors);
        IPool(pool).increaseLPAllowance(address(rfq), indexes, amounts);
        vm.stopPrank();

        (uint256 lp,) = IPool(pool).lenderInfo(index, user);
        assertEq(lp, 39.965028801848761892 ether);
        (lp,) = IPool(pool).lenderInfo(index, address(this));
        assertEq(lp, 0);

        vm.startPrank(user);
        (uint256 quoteAmount, uint256 lpAmount) =
            rfq.fillOrder(order, "", user, index, 2 ether, 1 ether, block.timestamp + 1 hours);

        IPool(pool).increaseLPAllowance(address(rfq), indexes, amounts);

        (quoteAmount, lpAmount) = rfq.fillOrder(order, "", user, index, 2 ether, 0.5 ether, block.timestamp + 1 hours);
        vm.stopPrank();

        assertEq(IERC20(weth).balanceOf(address(this)), 15.98646941270384781 ether);
        assertEq(IERC20(weth).balanceOf(user), 4.005438791757248656 ether);
        assertEq(IERC20(weth).balanceOf(address(rfq)), 0.008091795538903534 ether);
        (lp,) = IPool(pool).lenderInfo(index, user);
        assertEq(lp, 35.965028801848761892 ether);
        (lp,) = IPool(pool).lenderInfo(index, address(this));
        assertEq(lp, 4 ether);
    }
}
