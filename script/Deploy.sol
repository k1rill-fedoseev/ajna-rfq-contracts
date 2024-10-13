// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAjnaRFQ} from "../src/interfaces/IAjnaRFQ.sol";
import {IPool} from "../src/interfaces/IPool.sol";
import {AjnaRFQ} from "src/AjnaRFQ.sol";
import {AjnaRFQProxyActions} from "src/integration/AjnaRFQProxyActions.sol";

contract DeployScript is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        AjnaRFQ rfq = new AjnaRFQ{salt: 0}(vm.envAddress("OWNER"), 0.2 ether);
        AjnaRFQProxyActions proxyActions = new AjnaRFQProxyActions{salt: 0}(rfq);

        console.log("AjnaRFQ", address(rfq));
        console.log("AjnaRFQProxyActions", address(proxyActions));
        vm.stopBroadcast();
    }
}
