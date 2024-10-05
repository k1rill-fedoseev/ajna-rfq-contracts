// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";
import {IPool} from "../src/interfaces/IPool.sol";

contract AjnaPoolMock is IPool {
    address public immutable quoteTokenAddress;
    address public immutable collateralAddress;
    uint256 public immutable quoteTokenScale;

    constructor(address quoteTokenAddress_, address collateralTokenAddress_) {
        quoteTokenAddress = quoteTokenAddress_;
        collateralAddress = collateralTokenAddress_;
        quoteTokenScale = 10 ** (18 - IERC20Metadata(quoteTokenAddress_).decimals());
    }

    mapping(uint256 => uint256) public bucketExchangeRate;

    mapping(address => mapping(address => bool)) public approvedTransferors;
    mapping(uint256 => mapping(address => uint256)) public lp;
    mapping(uint256 => mapping(address => mapping(address => uint256))) public lpAllowance;

    function lenderInfo(uint256 index_, address lender_) external view returns (uint256, uint256) {
        return (lp[index_][lender_], 0);
    }

    function approveLPTransferors(address[] calldata transferors_) external {
        for (uint256 i = 0; i < transferors_.length; ++i) {
            approvedTransferors[msg.sender][transferors_[i]] = true;
        }
    }

    function increaseLPAllowance(address spender_, uint256[] calldata indexes_, uint256[] calldata amounts_) external {
        require(indexes_.length == amounts_.length, "size");
        for (uint256 i = 0; i < indexes_.length; ++i) {
            lpAllowance[indexes_[i]][spender_][msg.sender] += amounts_[i];
        }
    }

    function transferLP(address owner_, address newOwner_, uint256[] calldata indexes_) external {
        require(newOwner_ == msg.sender || approvedTransferors[newOwner_][msg.sender], "not approved");
        for (uint256 i = 0; i < indexes_.length; ++i) {
            uint256 index = indexes_[i];
            uint256 ownerLpBalance = lp[index][owner_];
            uint256 allowedAmount = lpAllowance[index][newOwner_][owner_];
            require(allowedAmount > 0, "zero allowance");

            if (ownerLpBalance < allowedAmount) {
                allowedAmount = ownerLpBalance;
            }

            lp[index][owner_] -= allowedAmount;
            lp[index][newOwner_] += allowedAmount;

            delete lpAllowance[index][newOwner_][owner_];
        }
    }

    function setLP(uint256 index_, address user_, uint256 balance_) external {
        lp[index_][user_] = balance_;
    }

    function setBucketExchangeRate(uint256 index_, uint256 rate_) external {
        bucketExchangeRate[index_] = rate_;
    }
}

contract WETH9 {
    string public name = "Wrapped Ether";
    string public symbol = "WETH";
    uint8 public decimals = 18;

    event Approval(address indexed src, address indexed guy, uint256 wad);
    event Transfer(address indexed src, address indexed dst, uint256 wad);
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        balanceOf[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 wad) public {
        require(balanceOf[msg.sender] >= wad);
        balanceOf[msg.sender] -= wad;
        payable(msg.sender).transfer(wad);
        emit Withdrawal(msg.sender, wad);
    }

    function totalSupply() public view returns (uint256) {
        return address(this).balance;
    }

    function approve(address guy, uint256 wad) public returns (bool) {
        allowance[msg.sender][guy] = wad;
        emit Approval(msg.sender, guy, wad);
        return true;
    }

    function transfer(address dst, uint256 wad) public returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint256 wad) public returns (bool) {
        require(balanceOf[src] >= wad);

        if (src != msg.sender && allowance[src][msg.sender] != type(uint256).max) {
            require(allowance[src][msg.sender] >= wad);
            allowance[src][msg.sender] -= wad;
        }

        balanceOf[src] -= wad;
        balanceOf[dst] += wad;

        emit Transfer(src, dst, wad);

        return true;
    }
}

contract MintableMockERC20 is MockERC20 {
    constructor(string memory name, string memory symbol, uint8 decimals) {
        initialize(name, symbol, decimals);
    }

    function mint(address to, uint256 value) public virtual {
        _mint(to, value);
    }

    function burn(address from, uint256 value) public virtual {
        _burn(from, value);
    }
}

contract AjnaFactoryMock {
    mapping(address => mapping(address => address)) pools;

    function deployedPools(bytes32, address collateral_, address quote_) external view returns (address) {
        return pools[collateral_][quote_];
    }

    function registerPool(address collateral_, address quote_, address pool_) external {
        pools[collateral_][quote_] = pool_;
    }
}
