// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ✅ Remix-compatible imports from OpenZeppelin GitHub
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.8.0/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.8.0/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.8.0/contracts/security/Pausable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.8.0/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.8.0/contracts/token/ERC20/utils/SafeERC20.sol";

interface IPancakeRouter {
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;

    function getAmountsOut(
        uint amountIn,
        address[] calldata path
    ) external view returns (uint[] memory amounts);
}

contract AdvancedBEP20 is ERC20, ERC20Burnable, Pausable, Ownable {
    using SafeERC20 for IERC20;

    // 🔥 Tokenomics
    uint256 public burnPercentage = 1; // 2% burn on transfer
    uint256 public minSwapAmount = 100 * 10**decimals();
    uint256 public maxSwapAmount = 10000 * 10**decimals();
    uint256 public dailyUSDTLimit = 50 * 10**18; // 50 USDT/day

    // 🧾 External contracts
    address public usdtToken;
    address public feeCollector;
    IPancakeRouter public pancakeRouter;
    IERC20 public oldToken;

    // 🔄 Migration tracking
    mapping(address => uint256) public oldTokenBalances;

    // 📊 Daily USDT sell tracking
    mapping(address => uint256) public dailyUSDTReceived;
    mapping(address => uint256) public lastSellTime;

    // 📢 Events
    event DailyUSDTLimitUpdated(uint256 newLimit);
    event BurnPercentageUpdated(uint256 newPercentage);
    event SwapLimitsUpdated(uint256 minAmount, uint256 maxAmount);
    event FeeCollectorUpdated(address newCollector);
    event TokensMigrated(address indexed user, uint256 amount);
    event TokensSwappedToUSDT(address indexed user, uint256 tokenAmount, uint256 usdtReceived);
    event TokensSwappedFromUSDT(address indexed user, uint256 usdtAmount, uint256 tokenReceived);
    event FeesCollected(uint256 usdtAmount);
    event TokensWithdrawn(address token, uint256 amount);

    constructor(
        string memory name_,
        string memory symbol_,
        address _usdtToken,
        address _router,
        address _oldToken
    ) ERC20(name_, symbol_) {
        usdtToken = _usdtToken;
        pancakeRouter = IPancakeRouter(_router);
        oldToken = IERC20(_oldToken);
        feeCollector = msg.sender;
        _mint(msg.sender, 1_000_000 * 10**decimals());
    }

    // 🔁 Transfer with burn
    function _transfer(address from, address to, uint256 amount) internal override whenNotPaused {
        uint256 burnAmount = (amount * burnPercentage) / 100;
        uint256 sendAmount = amount - burnAmount;
        super._burn(from, burnAmount);
        super._transfer(from, to, sendAmount);
    }

    // 🔄 Migration from old token (user-triggered)
    function migrate(uint256 amount) external {
        require(oldTokenBalances[msg.sender] == 0, "Already migrated");
        require(amount > 0, "Invalid amount");

        oldToken.safeTransferFrom(msg.sender, address(this), amount);
        oldTokenBalances[msg.sender] = amount;

        _mint(msg.sender, amount);
        emit TokensMigrated(msg.sender, amount);
    }

    // 🔁 Swap USDT to Token
    function swapUSDTToToken(uint256 amountIn, uint256 minOut) external {
        require(amountIn >= minSwapAmount && amountIn <= maxSwapAmount, "Swap amount out of bounds");
        IERC20(usdtToken).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(usdtToken).approve(address(pancakeRouter), amountIn);

        address[] memory path = new address[](2);
        path[0] = usdtToken;
        path[1] = address(this);

        pancakeRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, minOut, path, msg.sender, block.timestamp
        );

        emit TokensSwappedFromUSDT(msg.sender, amountIn, minOut);
    }

    // 🔁 Swap Token to USDT with daily USDT limit
    function swapTokenToUSDT(uint256 amountIn, uint256 minOut) external {
        require(amountIn >= minSwapAmount && amountIn <= maxSwapAmount, "Swap amount out of bounds");

        // Reset daily limit if 24 hours passed
        if (block.timestamp > lastSellTime[msg.sender] + 1 days) {
            dailyUSDTReceived[msg.sender] = 0;
            lastSellTime[msg.sender] = block.timestamp;
        }

        // Estimate USDT output
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = usdtToken;

        uint256[] memory amountsOut = pancakeRouter.getAmountsOut(amountIn, path);
        uint256 estimatedUSDT = amountsOut[1];

        // Enforce daily USDT limit
        require(dailyUSDTReceived[msg.sender] + estimatedUSDT <= dailyUSDTLimit, "Exceeds daily USDT sell limit");

        dailyUSDTReceived[msg.sender] += estimatedUSDT;

        _transfer(msg.sender, address(this), amountIn);
        _approve(address(this), address(pancakeRouter), amountIn);

        pancakeRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, minOut, path, msg.sender, block.timestamp
        );

        emit TokensSwappedToUSDT(msg.sender, amountIn, estimatedUSDT);
    }

    // 💰 Collect USDT fees
    function collectFees() external onlyOwner {
        uint256 balance = IERC20(usdtToken).balanceOf(address(this));
        require(balance > 0, "No fees to collect");
        IERC20(usdtToken).safeTransfer(feeCollector, balance);
        emit FeesCollected(balance);
    }

    // 🔓 Pause / Unpause
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // 💸 Withdraw tokens (owner only)
    function withdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(msg.sender, amount);
        emit TokensWithdrawn(token, amount);
    }

    // 🛠️ Update settings
    function setBurnPercentage(uint256 percent) external onlyOwner {
        require(percent <= 10, "Too high");
        burnPercentage = percent;
        emit BurnPercentageUpdated(percent);
    }

    function setSwapLimits(uint256 minAmount, uint256 maxAmount) external onlyOwner {
        minSwapAmount = minAmount;
        maxSwapAmount = maxAmount;
        emit SwapLimitsUpdated(minAmount, maxAmount);
    }

    function setFeeCollector(address collector) external onlyOwner {
        feeCollector = collector;
        emit FeeCollectorUpdated(collector);
    }

    function setDailyUSDTLimit(uint256 limit) external onlyOwner {
        require(limit > 0, "Limit must be positive");
        dailyUSDTLimit = limit;
        emit DailyUSDTLimitUpdated(limit);
    }
}
