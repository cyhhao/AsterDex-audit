// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IYieldProxy.sol";

interface IAsBNBMinter {
    function token() external view returns (IERC20);
    function mintAsBnb(uint256 amountIn) external returns (uint256);
    function mintAsBnb() external payable returns (uint256);
    function asBnb() external view returns (IERC20);
    function yieldProxy() external view returns (IYieldProxy);
}
