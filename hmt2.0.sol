// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IPancakeRouter {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
}

interface IPancakeFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IPancakePair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

contract Ownable is Context {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = _msgSender();
        emit OwnershipTransferred(address(0), _owner);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract HMTOKEN is Context, IERC20, Ownable {
    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) private _isExcludedFromFees;
    mapping (address => bool) private _isBlacklisted;

    uint256 private _totalSupply;
    uint256 private _maxSupply;
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    uint256 public burnPercentage = 1; // 1% burn on transfers
    uint256 public maxBuyUSD = 500 * 1e18; // $500 USD default
    uint256 public maxSellUSD = 300 * 1e18; // $300 USD default
    uint256 public maxWalletBalance;
    bool public isPaused;
    bool public burnEnabled = true;
    bool public tradingEnabled;
    uint256 public lastPriceUpdate;
    uint256 public priceUpdateInterval = 1 hours;

    address public oldTokenAddress;
    uint256 public migrationRate = 1; // 1:1 migration by default
    bool public migrationEnabled;

    IPancakeRouter public pancakeRouter;
    address public pancakePair;
    address public usdtPair;
    address public constant USDT = 0x55d398326f99059fF775485246999027B3197955; // BSC USDT address
    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c; // BSC WBNB address

    event TokenBurn(address indexed burner, uint256 value);
    event MigratedTokens(address indexed user, uint256 oldAmount, uint256 newAmount);
    event SwapAndLiquify(uint256 tokensSwapped, uint256 ethReceived, uint256 tokensIntoLiqudity);
    event MaxLimitsUpdated(uint256 newMaxBuy, uint256 newMaxSell);

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 initialSupply_,
        uint256 maxSupply_,
        uint256 maxWallet_
    ) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        _totalSupply = initialSupply_ * 10 ** decimals_;
        _maxSupply = maxSupply_ * 10 ** decimals_;
        maxWalletBalance = maxWallet_ * 10 ** decimals_;

        _balances[_msgSender()] = _totalSupply;
        emit Transfer(address(0), _msgSender(), _totalSupply);

        // Exclude owner and this contract from fees
        _isExcludedFromFees[owner()] = true;
        _isExcludedFromFees[address(this)] = true;

        // Initialize PancakeSwap
        IPancakeRouter _pancakeRouter = IPancakeRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E); // BSC Mainnet
        
        // Create token-WBNB pair
        pancakePair = IPancakeFactory(_pancakeRouter.factory())
            .createPair(address(this), _pancakeRouter.WETH());
            
        // Create token-USDT pair
        usdtPair = IPancakeFactory(_pancakeRouter.factory())
            .createPair(address(this), USDT);
            
        pancakeRouter = _pancakeRouter;
        lastPriceUpdate = block.timestamp;
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function maxSupply() public view returns (uint256) {
        return _maxSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()] - amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] - subtractedValue);
        return true;
    }

    // Get current token price in USDT
    function getTokenPrice() public view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = USDT;
        
        try pancakeRouter.getAmountsOut(10 ** _decimals, path) returns (uint[] memory amounts) {
            return amounts[1];
        } catch {
            // Fallback to BNB price if USDT pair fails
            path[1] = WBNB;
            uint[] memory amounts = pancakeRouter.getAmountsOut(10 ** _decimals, path);
            path[0] = WBNB;
            path[1] = USDT;
            uint[] memory usdAmounts = pancakeRouter.getAmountsOut(amounts[1], path);
            return usdAmounts[1];
        }
    }

    // Convert USD value to token amount
    function usdToToken(uint256 usdAmount) public view returns (uint256) {
        uint256 tokenPrice = getTokenPrice();
        require(tokenPrice > 0, "Price not available");
        return (usdAmount * (10 ** _decimals)) / tokenPrice;
    }

    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(!isPaused, "Token transfers are paused");
        require(!_isBlacklisted[sender] && !_isBlacklisted[recipient], "Address blacklisted");
        require(amount > 0, "Transfer amount must be greater than zero");

        // Update price if needed
        if (block.timestamp > lastPriceUpdate + priceUpdateInterval) {
            lastPriceUpdate = block.timestamp;
        }

        if (sender != owner() && recipient != owner()) {
            require(tradingEnabled, "Trading is not enabled yet");
            
            // Calculate dynamic limits
            uint256 currentMaxBuy = usdToToken(maxBuyUSD);
            uint256 currentMaxSell = usdToToken(maxSellUSD);
            
            // Buy restrictions
            if (sender == pancakePair || sender == usdtPair) {
                require(amount <= currentMaxBuy, "Buy amount exceeds max USD limit");
                require(_balances[recipient] + amount <= maxWalletBalance, "Wallet balance exceeds limit");
            }
            
            // Sell restrictions
            if (recipient == pancakePair || recipient == usdtPair) {
                require(amount <= currentMaxSell, "Sell amount exceeds max USD limit");
            }
        }

        uint256 burnAmount = 0;
        if (burnEnabled && !_isExcludedFromFees[sender] && !_isExcludedFromFees[recipient]) {
            burnAmount = (amount * burnPercentage) / 100;
        }

        uint256 transferAmount = amount - burnAmount;
        
        _balances[sender] -= amount;
        
        if (burnAmount > 0) {
            _totalSupply -= burnAmount;
            emit TokenBurn(sender, burnAmount);
            emit Transfer(sender, address(0), burnAmount);
        }
        
        _balances[recipient] += transferAmount;
        emit Transfer(sender, recipient, transferAmount);
    }

    // Token management functions
    function burn(uint256 amount) public virtual {
        require(_balances[_msgSender()] >= amount, "Insufficient balance");
        _balances[_msgSender()] -= amount;
        _totalSupply -= amount;
        emit TokenBurn(_msgSender(), amount);
        emit Transfer(_msgSender(), address(0), amount);
    }

    function pause() external onlyOwner {
        isPaused = true;
    }

    function unpause() external onlyOwner {
        isPaused = false;
    }

    function toggleBurn() external onlyOwner {
        burnEnabled = !burnEnabled;
    }

    function setBurnPercentage(uint256 percentage) external onlyOwner {
        require(percentage <= 10, "Burn percentage too high");
        burnPercentage = percentage;
    }

    function setMaxBuyUSD(uint256 usdAmount) external onlyOwner {
        require(usdAmount >= 10 * 1e18, "Min $10 limit");
        maxBuyUSD = usdAmount;
        emit MaxLimitsUpdated(usdAmount, maxSellUSD);
    }

    function setMaxSellUSD(uint256 usdAmount) external onlyOwner {
        require(usdAmount >= 5 * 1e18, "Min $5 limit");
        maxSellUSD = usdAmount;
        emit MaxLimitsUpdated(maxBuyUSD, usdAmount);
    }

    function setMaxWalletBalance(uint256 amount) external onlyOwner {
        maxWalletBalance = amount * 10 ** _decimals;
    }

    function excludeFromFees(address account, bool excluded) external onlyOwner {
        _isExcludedFromFees[account] = excluded;
    }

    function blacklistAddress(address account, bool blacklisted) external onlyOwner {
        _isBlacklisted[account] = blacklisted;
    }

    function enableTrading() external onlyOwner {
        tradingEnabled = true;
    }

    function setPriceUpdateInterval(uint256 interval) external onlyOwner {
        priceUpdateInterval = interval;
    }

    // Migration functions
    function setOldTokenAddress(address _oldToken) external onlyOwner {
        oldTokenAddress = _oldToken;
    }

    function setMigrationRate(uint256 rate) external onlyOwner {
        migrationRate = rate;
    }

    function toggleMigration() external onlyOwner {
        migrationEnabled = !migrationEnabled;
    }

    function migrateTokens(uint256 amount) external {
        require(migrationEnabled, "Migration is disabled");
        require(oldTokenAddress != address(0), "Old token not set");
        
        IERC20 oldToken = IERC20(oldTokenAddress);
        require(oldToken.balanceOf(_msgSender()) >= amount, "Insufficient old tokens");
        
        // Transfer old tokens to this contract
        oldToken.transferFrom(_msgSender(), address(this), amount);
        
        // Calculate and mint new tokens
        uint256 newAmount = amount * migrationRate;
        require(_totalSupply + newAmount <= _maxSupply, "Exceeds max supply");
        
        _balances[_msgSender()] += newAmount;
        _totalSupply += newAmount;
        
        emit MigratedTokens(_msgSender(), amount, newAmount);
        emit Transfer(address(0), _msgSender(), newAmount);
    }

    // PancakeSwap functions
    function swapTokensForUSDT(uint256 tokenAmount) external onlyOwner {
        require(tokenAmount <= _balances[address(this)], "Insufficient contract balance");
        
        _approve(address(this), address(pancakeRouter), tokenAmount);
        
        address[] memory path = new address[](3);
        path[0] = address(this);
        path[1] = pancakeRouter.WETH();
        path[2] = USDT;
        
        pancakeRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function swapTokensForBNB(uint256 tokenAmount) external onlyOwner {
        require(tokenAmount <= _balances[address(this)], "Insufficient contract balance");
        
        _approve(address(this), address(pancakeRouter), tokenAmount);
        
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = pancakeRouter.WETH();
        
        pancakeRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) external onlyOwner {
        _approve(address(this), address(pancakeRouter), tokenAmount);
        
        pancakeRouter.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0,
            0,
            owner(),
            block.timestamp
        );
    }

    // Safety functions
    function recoverBNB() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    function recoverBEP20(IERC20 tokenAddress, uint256 tokenAmount) external onlyOwner {
        tokenAddress.transfer(owner(), tokenAmount);
    }

    receive() external payable {}
}
