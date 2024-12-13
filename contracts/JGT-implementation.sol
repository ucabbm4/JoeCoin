// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../libraries/ERC20.sol";
import "../libraries/ReentrancyGuard.sol";
import "../libraries/Ownable.sol";
import "./JoeCoin-implementation.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";


// Introduce JGT with initial supply of 1 million tokens
contract JGTToken is ERC20, Ownable {
    constructor() ERC20("Joe's Governance Token", "JGT") Ownable(msg.sender) {
        _mint(msg.sender, 1000000 * 10**decimals()); 
    }
}

// Implement the staking mechanism for JGT tokens
contract JGTStaking is ReentrancyGuard, Ownable {
    JGTToken public immutable jgtToken;
    JoeCoin public immutable joeCoin;
    
    struct StakingInfo {
        uint256 amount;
        uint256 startTime;
        uint256 rewardDebt;
    }
    
    struct PoolInfo {
        uint256 lastRewardTime;
        uint256 accRewardPerShare;
        uint256 totalStaked;
    }
    
    mapping(address => StakingInfo) public stakingInfo;
    PoolInfo public poolInfo;
    
    // Set the staking reward rate to 100 JGT per day
    uint256 public rewardRate = 100 * 10**18; // 100 JGT per day
    uint256 public constant REWARD_PRECISION = 1e12;
    
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    
    constructor(address _jgtToken, address _joeCoin) Ownable(msg.sender) {
        jgtToken = JGTToken(_jgtToken);
        joeCoin = JoeCoin(_joeCoin);
        poolInfo.lastRewardTime = block.timestamp;
    }
    
    // Function to record stake 
    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot stake 0");
        updatePool();
        
        if (stakingInfo[msg.sender].amount > 0) {
            uint256 pending = calculateReward(msg.sender);
            if (pending > 0) {
                jgtToken.transfer(msg.sender, pending);
            }
        }
        
        joeCoin.transferFrom(msg.sender, address(this), amount);
        stakingInfo[msg.sender].amount += amount;
        stakingInfo[msg.sender].startTime = block.timestamp;
        stakingInfo[msg.sender].rewardDebt = stakingInfo[msg.sender].amount * 
            poolInfo.accRewardPerShare / REWARD_PRECISION;
        poolInfo.totalStaked += amount;
        
        emit Staked(msg.sender, amount);
    }
    
    // Function to withdraw stake
    function withdraw(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot withdraw 0");
        require(stakingInfo[msg.sender].amount >= amount, "Insufficient balance");
        
        updatePool();
        uint256 pending = calculateReward(msg.sender);
        
        stakingInfo[msg.sender].amount -= amount;
        stakingInfo[msg.sender].rewardDebt = stakingInfo[msg.sender].amount * 
            poolInfo.accRewardPerShare / REWARD_PRECISION;
        poolInfo.totalStaked -= amount;
        
        if (pending > 0) {
            jgtToken.transfer(msg.sender, pending);
        }
        joeCoin.transfer(msg.sender, amount);
        
        emit Withdrawn(msg.sender, amount);
        emit RewardClaimed(msg.sender, pending);
    }
    
    // Function to claim rewards
    function claimReward() external nonReentrant {
        updatePool();
        uint256 pending = calculateReward(msg.sender);
        require(pending > 0, "No rewards to claim");
        
        stakingInfo[msg.sender].rewardDebt = stakingInfo[msg.sender].amount * 
            poolInfo.accRewardPerShare / REWARD_PRECISION;
        
        jgtToken.transfer(msg.sender, pending);
        emit RewardClaimed(msg.sender, pending);
    }
    
    // Function to update the pool with rewards info
    function updatePool() public {
        if (block.timestamp <= poolInfo.lastRewardTime) {
            return;
        }
        
        if (poolInfo.totalStaked == 0) {
            poolInfo.lastRewardTime = block.timestamp;
            return;
        }
        
        uint256 timeElapsed = block.timestamp - poolInfo.lastRewardTime;
        uint256 reward = timeElapsed * rewardRate / 1 days;
        
        poolInfo.accRewardPerShare += reward * REWARD_PRECISION / poolInfo.totalStaked;
        poolInfo.lastRewardTime = block.timestamp;
    }
    
    // Function to calculate rewards for a user
    function calculateReward(address user) public view returns (uint256) {
        StakingInfo memory staker = stakingInfo[user];
        uint256 accRewardPerShare = poolInfo.accRewardPerShare;
        
        if (block.timestamp > poolInfo.lastRewardTime && poolInfo.totalStaked > 0) {
            uint256 timeElapsed = block.timestamp - poolInfo.lastRewardTime;
            uint256 reward = timeElapsed * rewardRate / 1 days;
            accRewardPerShare += reward * REWARD_PRECISION / poolInfo.totalStaked;
        }
        
        return (staker.amount * accRewardPerShare / REWARD_PRECISION) - staker.rewardDebt;
    }
    
    // Governance setters
    function setRewardRate(uint256 _rewardRate) external onlyOwner {
        require(_rewardRate > 0, "Invalid reward rate");
        rewardRate = _rewardRate;
    }
}

// Implement the liquidity mining mechanism for JGT tokens
contract LiquidityMining is ReentrancyGuard, Ownable {
    JGTToken public immutable jgtToken;
    JoeCoin public immutable joeCoin;
    
    struct UserInfo {
        uint256 lpAmount;
        uint256 rewardDebt;
    }
    
    struct PoolInfo {
        uint256 lastRewardTime;
        uint256 accRewardPerShare;
        uint256 totalLpTokens;
    }
    
    mapping(address => UserInfo) public userInfo;
    PoolInfo public poolInfo;
    
    uint256 public rewardRate = 200 * 10**18; // 200 JGT per day for LP providers
    uint256 public constant REWARD_PRECISION = 1e12;
    
    event LiquidityAdded(address indexed user, uint256 amount);
    event LiquidityRemoved(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount);
    
    constructor(address _jgtToken, address _joeCoin) Ownable(msg.sender) {
        jgtToken = JGTToken(_jgtToken);
        joeCoin = JoeCoin(_joeCoin);
        poolInfo.lastRewardTime = block.timestamp;
    }
    
    // Add liquidity to the pool
    function addLiquidity(uint256 lpAmount) external nonReentrant {
        require(lpAmount > 0, "Cannot add 0 liquidity");
        updatePool();
        
        if (userInfo[msg.sender].lpAmount > 0) {
            uint256 pending = calculateReward(msg.sender);
            if (pending > 0) {
                jgtToken.transfer(msg.sender, pending);
            }
        }
        
        // Transfer LP tokens (placeholder - in real implementation would use actual LP tokens)
        joeCoin.transferFrom(msg.sender, address(this), lpAmount);
        userInfo[msg.sender].lpAmount += lpAmount;
        userInfo[msg.sender].rewardDebt = userInfo[msg.sender].lpAmount * 
            poolInfo.accRewardPerShare / REWARD_PRECISION;
        poolInfo.totalLpTokens += lpAmount;
        
        emit LiquidityAdded(msg.sender, lpAmount);
    }
    
    // Remove liquidity from the pool
    function removeLiquidity(uint256 lpAmount) external nonReentrant {
        require(lpAmount > 0, "Cannot remove 0 liquidity");
        require(userInfo[msg.sender].lpAmount >= lpAmount, "Insufficient LP tokens");
        
        updatePool();
        uint256 pending = calculateReward(msg.sender);
        
        userInfo[msg.sender].lpAmount -= lpAmount;
        userInfo[msg.sender].rewardDebt = userInfo[msg.sender].lpAmount * 
            poolInfo.accRewardPerShare / REWARD_PRECISION;
        poolInfo.totalLpTokens -= lpAmount;
        
        if (pending > 0) {
            jgtToken.transfer(msg.sender, pending);
        }
        joeCoin.transfer(msg.sender, lpAmount);
        
        emit LiquidityRemoved(msg.sender, lpAmount);
        emit RewardPaid(msg.sender, pending);
    }
    
    // Update the pool with rewards info
    function updatePool() public {
        if (block.timestamp <= poolInfo.lastRewardTime) {
            return;
        }
        
        if (poolInfo.totalLpTokens == 0) {
            poolInfo.lastRewardTime = block.timestamp;
            return;
        }
        
        uint256 timeElapsed = block.timestamp - poolInfo.lastRewardTime;
        uint256 reward = timeElapsed * rewardRate / 1 days;
        
        poolInfo.accRewardPerShare += reward * REWARD_PRECISION / poolInfo.totalLpTokens;
        poolInfo.lastRewardTime = block.timestamp;
    }
    
    // Calculate rewards for a user
    function calculateReward(address user) public view returns (uint256) {
        UserInfo memory lpUser = userInfo[user];
        uint256 accRewardPerShare = poolInfo.accRewardPerShare;
        
        if (block.timestamp > poolInfo.lastRewardTime && poolInfo.totalLpTokens > 0) {
            uint256 timeElapsed = block.timestamp - poolInfo.lastRewardTime;
            uint256 reward = timeElapsed * rewardRate / 1 days;
            accRewardPerShare += reward * REWARD_PRECISION / poolInfo.totalLpTokens;
        }
        
        return (lpUser.lpAmount * accRewardPerShare / REWARD_PRECISION) - lpUser.rewardDebt;
    }
    
    // Governance setters
    function setRewardRate(uint256 _rewardRate) external onlyOwner {
        require(_rewardRate > 0, "Invalid reward rate");
        rewardRate = _rewardRate;
    }
}

// Implement the Range Bound Stability (RBS) mechanism for JoeCoin
// is Ownable to restrict functions to just the owner
contract JoeCoinRBS is Ownable {
    JoeCoinPriceOracle public oracle;

    // Contract can only accept parameter updates from the governance contract
    address public governance;
    
    modifier onlyGovernance() {
        require(msg.sender == governance, "Only governance can call");
        _;
    }

    // / State variables for baseline values (90-day Moving Averages)
    uint256 public baselineSentiment;
    uint256 public baselineVolatility;
    uint256 public baselineOBI;
    
    // Current values
    uint256 public currentSentiment;
    uint256 public currentVolatility;
    uint256 public currentOBI;

    uint256 public sentimentRisk;
    uint256 public volatilityRisk;
    uint256 public imbalanceRisk;
    
    /// Parameters structs separated by type
    struct BaseParameters {
        uint256 C0;  // Base cushion
        uint256 W0;  // Base wall
    }
    
    struct SensitivityParameters {
        uint256 alpha;  // Sentiment sensitivity
        uint256 beta;   // Volatility sensitivity
        uint256 gamma;  // Imbalance sensitivity
    }
    
    BaseParameters public baseParams;
    SensitivityParameters public sensitivities;
    
    // Price bounds sturct
    struct PriceBounds {
        uint256 upperWall;
        uint256 upperCushion;
        uint256 lowerCushion;
        uint256 lowerWall;
    }
    
    PriceBounds public bounds;
    
    // Scaling factor for precision
    uint256 constant PRECISION = 1e18;
    
    // Parameter bounds as per specifications in the whitepaper
    uint256 constant MIN_ALPHA_BETA = 1e17;  // 0.1 in PRECISION
    uint256 constant MAX_ALPHA_BETA = 1e18;  // 1 in PRECISION
    uint256 constant MIN_GAMMA = 5e16;       // 0.05 in PRECISION
    uint256 constant MAX_GAMMA = 5e17;       // 0.5 in PRECISION


    // emit the event when bounds are updated
    event BoundsUpdated(
        uint256 upperWall,
        uint256 upperCushion,
        uint256 lowerCushion,
        uint256 lowerWall
    );

    // emit the event when sensitivity parameters are updated
    event SensitivityParametersUpdated(
        uint256 alpha,
        uint256 beta,
        uint256 gamma
    );
    
    // emit the event when base parameters are updated
    event BaseParametersUpdated(
        uint256 C0,
        uint256 W0
    );

    // emit the event when governance is updated
    event GovernanceUpdated(address newGovernance);

    constructor(
        uint256 _C0,
        uint256 _W0,
        uint256 _alpha,
        uint256 _beta,
        uint256 _gamma,
        address _oracle
    ) Ownable(msg.sender) {
        require(_alpha >= MIN_ALPHA_BETA && _alpha <= MAX_ALPHA_BETA, "Invalid alpha");
        require(_beta >= MIN_ALPHA_BETA && _beta <= MAX_ALPHA_BETA, "Invalid beta");
        require(_gamma >= MIN_GAMMA && _gamma <= MAX_GAMMA, "Invalid gamma");
        baseParams = BaseParameters({
            C0: _C0,
            W0: _W0
        });
        
        sensitivities = SensitivityParameters({
            alpha: _alpha,
            beta: _beta,
            gamma: _gamma
        });

        oracle = JoeCoinPriceOracle(_oracle);
        
        // Call _updateBounds() after setting parameters
        _updateBounds();
    }
    
    // Calculate Sentiment Risk according to specification
    function calculateSentimentRisk() public view returns (uint256) {
        if (baselineSentiment == 0) return 0;

        // Check if baseline > current
        if (baselineSentiment > currentSentiment) {
            // (1 - current/baseline) * PRECISION
            return (PRECISION - (currentSentiment * PRECISION / baselineSentiment));
        } else {
            // (current/baseline - 1) * PRECISION
            return ((currentSentiment * PRECISION / baselineSentiment) - PRECISION);
        }
    }
    
    // Calculate Volatility Risk according to specification
    function calculateVolatilityRisk() public view returns (uint256) {
        if (baselineVolatility == 0) return 0;

        // Check if current > baseline
        if (currentVolatility > baselineVolatility) {
            // (current/baseline - 1) * PRECISION
            return ((currentVolatility * PRECISION / baselineVolatility) - PRECISION);
        } else {
            // (1 - current/baseline) * PRECISION
            return (PRECISION - (currentVolatility * PRECISION / baselineVolatility));
        }
    }
    
    // Calculate Imbalance Risk according to specification
    function calculateImbalanceRisk() public view returns (uint256) {
        if (baselineOBI == 0) return 0;

        // Check if baseline > current
        if (baselineOBI > currentOBI) {
            // (1 - current/baseline) * PRECISION
            return (PRECISION - (currentOBI * PRECISION / baselineOBI));
        } else {
            // (current/baseline - 1) * PRECISION
            return ((currentOBI * PRECISION / baselineOBI) - PRECISION);
        }
    }

    // Calculate aggregate risk score R according to specification
    function calculateRiskScore() public view returns (uint256) {
        uint256 sentimentComponent = sensitivities.alpha * calculateSentimentRisk();
        uint256 volatilityComponent = sensitivities.beta * calculateVolatilityRisk();
        uint256 imbalanceComponent = sensitivities.gamma * calculateImbalanceRisk();
        
        return (sentimentComponent + volatilityComponent + imbalanceComponent) / PRECISION;
    }

    // Function to set governance address (can only be called once by owner)
    function setGovernance(address _governance) external onlyOwner {
        require(governance == address(0), "Governance already set");
        require(_governance != address(0), "Invalid governance address");
        governance = _governance;
        emit GovernanceUpdated(_governance);
    }

    // Update the baseline values (90-day Moving Averages)
    function updateBaselines(
        uint256 _baselineSentiment,
        uint256 _baselineVolatility,
        uint256 _baselineOBI
    ) external onlyOwner {
        baselineSentiment = _baselineSentiment;
        baselineVolatility = _baselineVolatility;
        baselineOBI = _baselineOBI;
        _updateBounds();
    }

    // Update current values
    function updateCurrentValues(
        uint256 _currentSentiment,
        uint256 _currentVolatility,
        uint256 _currentOBI
    ) external onlyOwner {
        currentSentiment = _currentSentiment;
        currentVolatility = _currentVolatility;
        currentOBI = _currentOBI;
        _updateBounds();
    }

    // Update risk factors based on oracle/external data
    function updateRiskFactors(
    ) external onlyOwner {
        oracle.updatePrice();

        // Calculate volatility risk
        uint256 volatility = oracle.calculateVolatility();
        volatilityRisk = volatility * PRECISION / oracle.getMovingAverage();
        
        // Calculate price deviation from moving average
        uint256 currentPrice = oracle.getLatestPrice();
        uint256 movingAvg = oracle.getMovingAverage();
        
        if (currentPrice > movingAvg) {
            imbalanceRisk = (currentPrice - movingAvg) * PRECISION / movingAvg;
        } else {
            imbalanceRisk = (movingAvg - currentPrice) * PRECISION / movingAvg;
        }
        
        // Update bounds based on new risk factors
        _updateBounds();
    }

    // Update only sensitivity parameters (governance controlled)
    function updateSensitivityParameters(
        uint256 _alpha,
        uint256 _beta,
        uint256 _gamma
    ) external onlyGovernance {
        require(_alpha >= MIN_ALPHA_BETA && _alpha <= MAX_ALPHA_BETA, "Invalid alpha");
        require(_beta >= MIN_ALPHA_BETA && _beta <= MAX_ALPHA_BETA, "Invalid beta");
        require(_gamma >= MIN_GAMMA && _gamma <= MAX_GAMMA, "Invalid gamma");

        sensitivities.alpha = _alpha;
        sensitivities.beta = _beta;
        sensitivities.gamma = _gamma;
        
        _updateBounds();
        
        emit SensitivityParametersUpdated(_alpha, _beta, _gamma);
    }

    // Update base parameters (owner controlled)
    function updateBaseParameters(
        uint256 _C0,
        uint256 _W0
    ) external onlyOwner {
        require(_C0 > 0, "Invalid C0");
        require(_W0 > 0, "Invalid W0");
        
        baseParams.C0 = _C0;
        baseParams.W0 = _W0;
        
        _updateBounds();
        
        emit BaseParametersUpdated(_C0, _W0);
    }
    
    // Internal function to update bounds based on risk score
    function _updateBounds() internal {
        uint256 R = calculateRiskScore();
        
        // Update cushion and wall parameters based on risk score
        uint256 Cnew = baseParams.C0 * (PRECISION + R) / PRECISION;
        uint256 Wnew = baseParams.W0 * (PRECISION + R) / PRECISION;
        
        // Calculate new bounds
        bounds = PriceBounds({
            upperWall: PRECISION + Wnew,
            upperCushion: PRECISION + Cnew,
            lowerCushion: PRECISION - Cnew,
            lowerWall: PRECISION - Wnew
        });
        
        emit BoundsUpdated(
            bounds.upperWall,
            bounds.upperCushion,
            bounds.lowerCushion,
            bounds.lowerWall
        );
    }
    
    // View function to get current bounds
    function getCurrentBounds() external view returns (PriceBounds memory) {
        return bounds;
    }
}