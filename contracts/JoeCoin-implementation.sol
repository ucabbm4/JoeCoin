// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../libraries/ERC20.sol";
import "../libraries/ReentrancyGuard.sol";
import "../libraries/Ownable.sol";

// Price Oracle Interface
interface IJoeCoinOracle {
    function getLatestPrice() external view returns (uint256);
    function getPrice(address asset) external view returns (uint256);
    function setPrice(address asset, uint256 price) external;
    function updatePrice() external;
    function calculateVolatility() external view returns (uint256);
    function getMovingAverage() external view returns (uint256);
}

// Add in joecoin RBS interface
// JoeCoinRBS interface - the getCurrentBounds function returns the current price bounds and 4x values
interface IJoeCoinRBS {
    function getCurrentBounds() external view returns (
        uint256 upperWall,
        uint256 upperCushion,
        uint256 lowerCushion,
        uint256 lowerWall
    );
}


// JoeCoin - The stablecoin token
contract JoeCoin is ERC20, Ownable {
    address public governance;
    IJoeCoinRBS public stabilizer;
    IJoeCoinOracle public priceOracle;

    // Stabilization related variables
    bool public stabilizationActive;
    uint256 public constant PRECISION = 1e18;
    
    event StabilizerUpdated(address newStabilizer);
    event PriceOracleUpdated(address newOracle);
    event StabilizationToggled(bool isActive);


    constructor() ERC20("JoeCoin", "JOE") Ownable(msg.sender) {
    // Set initial state of stabilization i.e. turn it on    
        stabilizationActive = true; // Set initial state
    }

    function mint(address to, uint256 amount) external onlyOwner {
    // Add requirement that stability conditions are met        
        require(checkStabilityConditions(), "Stability conditions not met");
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
    // Add requirement that stability conditions are met
        require(checkStabilityConditions(), "Stability conditions not met");  
        _burn(from, amount);
    }

    // Checks if the current price is within the stabilization bounds
    function checkStabilityConditions() public view returns (bool) {
    if (!stabilizationActive || address(stabilizer) == address(0)) {
        return true;
    }
    
    uint256 currentPrice = priceOracle.getLatestPrice();
    
    (
        uint256 upperWall,
        uint256 upperCushion,
        uint256 lowerCushion,
        uint256 lowerWall
    ) = stabilizer.getCurrentBounds();
    
    // Check both walls and cushions
    bool withinWalls = currentPrice >= lowerWall && currentPrice <= upperWall;
    bool withinCushions = currentPrice >= lowerCushion && currentPrice <= upperCushion;
    
    return withinWalls && withinCushions;
    }

    // Function to get the current stability metrics
    function getStabilityMetrics() external view returns (
        bool isStable,
        uint256 currentPrice,
        uint256 upperWall,
        uint256 upperCushion,
        uint256 lowerCushion,
        uint256 lowerWall
    ) {
        isStable = checkStabilityConditions();
        currentPrice = priceOracle.getPrice(address(this));
        
        (
            upperWall,
            upperCushion,
            lowerCushion,
            lowerWall
        ) = stabilizer.getCurrentBounds();
        
        return (
            isStable,
            currentPrice,
            upperWall,
            upperCushion,
            lowerCushion,
            lowerWall
        );
    }

    modifier onlyGovernance() {
        require(msg.sender == governance, "Only governance can call");
        _;
    }

    // Function to set the governance address (can only be set once)
    function setGovernance(address _governance) external onlyOwner {
        require(governance == address(0), "Governance already set");
        require(_governance != address(0), "Invalid governance address");
        governance = _governance;
        emit GovernanceUpdated(_governance);
    }

    // Admin functions that are driven by the governance contract
    function setStabilizer(address _stabilizer) external onlyGovernance {
        require(_stabilizer != address(0), "Invalid stabilizer address");
        stabilizer = IJoeCoinRBS(_stabilizer);
        emit StabilizerUpdated(_stabilizer);
    }

    function setPriceOracle(address _priceOracle) external onlyGovernance {
        require(_priceOracle != address(0), "Invalid oracle address");
        priceOracle = JoeCoinPriceOracle(_priceOracle);
        emit PriceOracleUpdated(_priceOracle);
    }

    // if the stabilization is active (t/f) then 
    function toggleStabilization(bool _active) external onlyGovernance {
        stabilizationActive = _active;
        emit StabilizationToggled(_active);
    }

    event GovernanceUpdated(address newGovernance);
}

// Vault contract to manage collateral and debt
contract JoeVault is ReentrancyGuard, Ownable {
    struct Vault {
        uint256 collateralAmount;
        uint256 debtAmount;
        uint256 lastInterestUpdate;
    }

    JoeCoin public immutable joeCoin;
    IJoeCoinOracle public immutable priceOracle;
    
    mapping(address => Vault) public vaults;
    mapping(address => bool) public supportedCollateral;
    
    uint256 public minimumCollateralRatio = 150;    // 150%
    uint256 public liquidationThreshold = 130;      // 130%
    uint256 public stabilityFee = 5;                // 0.5% annual
    uint256 public liquidationPenalty = 130;        // 13%
    
    event VaultCreated(address indexed owner, uint256 collateralAmount, uint256 debtAmount);
    event VaultModified(address indexed owner, uint256 collateralAmount, uint256 debtAmount);
    event VaultLiquidated(address indexed owner, address liquidator, uint256 debtCovered);

    constructor(address _joeCoin, address _priceOracle) Ownable(msg.sender) {
        joeCoin = JoeCoin(_joeCoin);
        priceOracle = JoeCoinPriceOracle(_priceOracle);
    }

    // Sets the collateral token as supported or not
    function setCollateralSupport(address collateral, bool supported) external onlyOwner {
        supportedCollateral[collateral] = supported;
    }

    function createVault(
        address collateralToken,
        uint256 collateralAmount,
        uint256 debtAmount
    ) external nonReentrant {
        require(supportedCollateral[collateralToken], "Unsupported collateral");
        
        IERC20(collateralToken).transferFrom(msg.sender, address(this), collateralAmount);
        
        uint256 collateralValue = getCollateralValue(collateralToken, collateralAmount);
        require(
            collateralValue * 100 >= debtAmount * minimumCollateralRatio,
            "Insufficient collateral ratio"
        );
        
        Vault storage vault = vaults[msg.sender];
        vault.collateralAmount += collateralAmount;
        vault.debtAmount += debtAmount;
        vault.lastInterestUpdate = block.timestamp;
        
        joeCoin.mint(msg.sender, debtAmount);
        
        emit VaultCreated(msg.sender, collateralAmount, debtAmount);
    }

    // Repay debt and optionally withdraw collateral
    function repayDebt(
        address collateralToken,
        uint256 repayAmount,
        uint256 collateralToWithdraw
    ) external nonReentrant {
        Vault storage vault = vaults[msg.sender];
        require(vault.debtAmount >= repayAmount, "Repay amount too high");
        
        uint256 fee = calculateStabilityFee(vault);
        uint256 totalRepayment = repayAmount + fee;
        
        joeCoin.transferFrom(msg.sender, address(this), totalRepayment);
        joeCoin.burn(address(this), totalRepayment);
        
        vault.debtAmount -= repayAmount;
        
        // Withdraw collateral if requested
        if (collateralToWithdraw > 0) {
            require(vault.collateralAmount >= collateralToWithdraw, "Insufficient collateral");
            
            uint256 remainingCollateral = vault.collateralAmount - collateralToWithdraw;
            uint256 remainingCollateralValue = getCollateralValue(
                collateralToken,
                remainingCollateral
            );
            
            require(
                vault.debtAmount == 0 || 
                remainingCollateralValue * 100 >= vault.debtAmount * minimumCollateralRatio,
                "Would breach collateral ratio"
            );
            
            vault.collateralAmount = remainingCollateral;
            IERC20(collateralToken).transfer(msg.sender, collateralToWithdraw);
        }
        
        vault.lastInterestUpdate = block.timestamp;
        emit VaultModified(msg.sender, vault.collateralAmount, vault.debtAmount);
    }

    function liquidateVault(
        address vaultOwner,
        address collateralToken,
        uint256 debtToCover
    ) external nonReentrant {
        Vault storage vault = vaults[vaultOwner];
        require(isLiquidatable(vaultOwner, collateralToken), "Vault not liquidatable");
        require(debtToCover <= vault.debtAmount, "Debt amount too high");
        
        uint256 collateralPrice = priceOracle.getPrice(collateralToken);
        uint256 collateralToSeize = (debtToCover * liquidationPenalty * 1e18) / 
                                  (collateralPrice * 100);
        
        require(collateralToSeize <= vault.collateralAmount, "Insufficient collateral");
        
        joeCoin.transferFrom(msg.sender, address(this), debtToCover);
        joeCoin.burn(address(this), debtToCover);
        
        vault.debtAmount -= debtToCover;
        vault.collateralAmount -= collateralToSeize;
        
        IERC20(collateralToken).transfer(msg.sender, collateralToSeize);
        
        emit VaultLiquidated(vaultOwner, msg.sender, debtToCover);
    }

    function getCollateralValue(address collateralToken, uint256 amount) public view returns (uint256) {
        uint256 price = priceOracle.getPrice(collateralToken);
        return (price * amount) / 1e18;
    }
    
    function calculateStabilityFee(Vault memory vault) public view returns (uint256) {
        uint256 timeElapsed = block.timestamp - vault.lastInterestUpdate;
        return (vault.debtAmount * stabilityFee * timeElapsed) / (365 days * 1000);
    }
    
    function isLiquidatable(address vaultOwner, address collateralToken) public view returns (bool) {
        Vault memory vault = vaults[vaultOwner];
        if (vault.debtAmount == 0) return false;
        
        uint256 collateralValue = getCollateralValue(collateralToken, vault.collateralAmount);
        return collateralValue * 100 < vault.debtAmount * liquidationThreshold;
    }

    function setMinimumCollateralRatio(uint256 _ratio) external onlyOwner {
        require(_ratio >= 100, "Invalid ratio");
        minimumCollateralRatio = _ratio;
    }
    
    function setLiquidationThreshold(uint256 _threshold) external onlyOwner {
        require(_threshold >= 100 && _threshold < minimumCollateralRatio, "Invalid threshold");
        liquidationThreshold = _threshold;
    }
    
    function setStabilityFee(uint256 _fee) external onlyOwner {
        stabilityFee = _fee;
    }
    
    function setLiquidationPenalty(uint256 _penalty) external onlyOwner {
        require(_penalty >= 100, "Invalid penalty");
        liquidationPenalty = _penalty;
    }
}

// Price Oracle Implementation
contract JoeCoinPriceOracle is IJoeCoinOracle, Ownable {
    mapping(address => uint256) public prices;
    
    uint256[] private priceHistory;
    uint256 private constant MAX_HISTORY_LENGTH = 24; // Store 24 hours of price history
    uint256 private constant UPDATE_INTERVAL = 1 hours;
    uint256 public lastUpdateTime;
    
    constructor() Ownable(msg.sender) {
        lastUpdateTime = block.timestamp;
    }
    
    // Set the price of an asset
    function setPrice(address asset, uint256 price) external override onlyOwner {
        prices[asset] = price;
        _updatePriceHistory(price);
    }
    
    // Update the price history every hour
    function updatePrice() external override {
        require(block.timestamp >= lastUpdateTime + UPDATE_INTERVAL, "Too soon to update");
        uint256 currentPrice = getLatestPrice();
        _updatePriceHistory(currentPrice);
        lastUpdateTime = block.timestamp;
    }
    
    // Get the price of an asset
    function getPrice(address asset) external view override returns (uint256) {
        require(prices[asset] > 0, "Price not set");
        return prices[asset];
    }

    // Get the latest price of the asset
    function getLatestPrice() public view override returns (uint256) {
        return prices[msg.sender];
    }
    
    // Calculate the volatility of the asset
    function calculateVolatility() external view override returns (uint256) {
        require(priceHistory.length >= 2, "Insufficient price history");
        
        uint256 avgPrice = getMovingAverage();
        uint256 sumSquaredDeviations = 0;
        
        for (uint i = 0; i < priceHistory.length; i++) {
            if (priceHistory[i] > avgPrice) {
                sumSquaredDeviations += ((priceHistory[i] - avgPrice) ** 2);
            } else {
                sumSquaredDeviations += ((avgPrice - priceHistory[i]) ** 2);
            }
        }
        
        return sqrt(sumSquaredDeviations / priceHistory.length);
    }
    
    // Get the moving average of the asset price
    function getMovingAverage() public view override returns (uint256) {
        require(priceHistory.length > 0, "No price history");
        
        uint256 sum = 0;
        for (uint i = 0; i < priceHistory.length; i++) {
            sum += priceHistory[i];
        }
        
        return sum / priceHistory.length;
    }
    
    // Update the price history
    function _updatePriceHistory(uint256 price) internal {
        if (priceHistory.length >= MAX_HISTORY_LENGTH) {
            // Remove oldest price
            for (uint i = 0; i < priceHistory.length - 1; i++) {
                priceHistory[i] = priceHistory[i + 1];
            }
            priceHistory[priceHistory.length - 1] = price;
        } else {
            priceHistory.push(price);
        }
    }
    
    // Utility function to calculate square root
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        
        return y;
    }
}