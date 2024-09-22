// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {AjnaRFQ} from "src/AjnaRFQ.sol";
import {AjnaPoolMock} from "../test/Mocks.sol";

contract DeployMocksScript is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        AjnaRFQ rfq = new AjnaRFQ(address(this), 0.2 ether);
        address quote = address(deployMockERC20("Quote", "Q", 18));
        AjnaPoolMock pool = new AjnaPoolMock(address(quote));
        vm.stopBroadcast();

        console.logAddress(address(rfq));
        console.logAddress(quote);
        console.logAddress(address(pool));
    }
}
