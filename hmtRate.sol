// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice Minimal PancakeSwap V2 router interface
interface IPancakeRouter {
    function getAmountsOut(
        uint256 amountIn,
        address[] calldata path
    ) external view returns (uint256[] memory amounts);
}

/// @notice Minimal ERC-20 interface for decimals()
interface IERC20 {
    function decimals() external view returns (uint8);
}

contract HmtPriceConsumer {
    IPancakeRouter public immutable router;
    address        public immutable HMT;
    address        public immutable USDT;

    /// @param _router     PancakeSwap V2 router (e.g. 0x10ED43C718714eb63d5aA57B78B54704E256024E)
    /// @param _hmtAddress Your HMT token’s BSC address
    /// @param _usdtAddress USDT on BSC (0x55d398326f99059fF775485246999027B3197955)
    constructor(
        address _router,
        address _hmtAddress,
        address _usdtAddress
    ) {
        require(_router     != address(0)
             && _hmtAddress != address(0)
             && _usdtAddress!= address(0),
             "Zero address");

        router = IPancakeRouter(_router);
        HMT    = _hmtAddress;
        USDT   = _usdtAddress;
    }

    /// @notice How many HMT you get for `usdtAmount` USDT
    /// @dev `usdtAmount` must be in USDT’s base units (e.g. to ask for 10 USDT, pass 10 * 10^18)
    function getHmtForUsdt(uint256 usdtAmount)
        public view
        returns (uint256 hmtAmount)
    {
        address[] memory path = new address[](2);
        path[0] = USDT;
        path[1] = HMT;



        uint256[] memory amounts = router.getAmountsOut(usdtAmount, path);
        hmtAmount = amounts[1];
    }

    /// @notice Raw HMT amount returned for exactly 1 USDT
    function getLiveRate() external view returns (uint256) {
        uint8   d = IERC20(USDT).decimals();
        uint256 oneUsdt = 10 ** d;
        return getHmtForUsdt(oneUsdt);
    }
}
