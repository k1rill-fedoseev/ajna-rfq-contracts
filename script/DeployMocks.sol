// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";
import {AjnaRFQ} from "src/AjnaRFQ.sol";
import {AjnaFactoryMock, AjnaPoolMock, MintableMockERC20} from "../test/Mocks.sol";

contract DeployMocksScript is Test, Script {
    function setUp() public {}

    function run() public {
        address deployer = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        address user1 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
        address user2 = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;

        vm.startBroadcast(deployer);
        AjnaRFQ rfq = new AjnaRFQ(address(this), 0.2 ether);
        MintableMockERC20 quote = new MintableMockERC20("Quote", "Q", 18);
        AjnaPoolMock pool = new AjnaPoolMock(address(quote), makeAddr("collateral"));
        AjnaFactoryMock factory = new AjnaFactoryMock();
        factory.registerPool(makeAddr("collateral"), address(quote), address(pool));

        pool.setBucketExchangeRate(1234, 1.123123123123123123 ether);
        pool.setLP(1234, user1, 6.123123123123123123 ether);
        quote.mint(user2, 10 ether);
        vm.stopBroadcast();

        address[] memory transferors = new address[](1);
        transferors[0] = address(rfq);
        uint256[] memory indices = new uint256[](1);
        indices[0] = 1234;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = type(uint256).max;

        vm.startBroadcast(user1);
        pool.approveLPTransferors(transferors);
        pool.increaseLPAllowance(address(rfq), indices, amounts);
        vm.stopBroadcast();

        vm.startBroadcast(user2);
        pool.approveLPTransferors(transferors);
        quote.approve(address(rfq), type(uint256).max);
        vm.stopBroadcast();

        console.log("rfq", address(rfq));
        console.log("quote", address(quote));
        console.log("pool", address(pool));
        console.log("factory", address(factory));
    }
}
