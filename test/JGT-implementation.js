const { expect } =require("chai");
const { ethers } =require("hardhat");

// Testing the JGTToken and JGTStaking contracts
describe("JGTToken and JGTStaking", function () {
  let owner, userOne, userTwo;
  let jgtToken, joeCoin, jgtStaking;
  
  const oneDay =60*24*60; // 60 min * 24 hours * 60 seconds

  beforeEach(async function () {
    [owner, userOne, userTwo] =await ethers.getSigners();

    // Deploying JGTToken
    const JGTToken =await ethers.getContractFactory("JGTToken");
    jgtToken =await JGTToken.deploy();
    const jgtTokenAddress =await jgtToken.getAddress();

    // Deploying JoeCoin
    const JoeCoin =await ethers.getContractFactory("JoeCoin");
    joeCoin =await JoeCoin.deploy();
    const joeCoinAddress =await joeCoin.getAddress();

    // Deploying JGTStaking
    const JGTStaking =await ethers.getContractFactory("JGTStaking");
    jgtStaking =await JGTStaking.deploy(jgtTokenAddress, joeCoinAddress);
    const jgtStakingAddress =await jgtStaking.getAddress();

    // Minting JoeCoin and distributing to users
    const mintAmount =ethers.parseEther("1000");
    await joeCoin.mint(userOne.address, mintAmount);
    await joeCoin.mint(userTwo.address, mintAmount);

    // Transfering JGT tokens to the staking contract as rewards
    const rewardAmount =ethers.parseEther("10000");
    await jgtToken.transfer(jgtStakingAddress, rewardAmount);

    // Approving staking contract to spend JoeCoin for both users
    await joeCoin.connect(userOne).approve(jgtStakingAddress, mintAmount);
    await joeCoin.connect(userTwo).approve(jgtStakingAddress, mintAmount);
  });

  // Testing the staking functionality
  describe("Staking", function () {
    it("Should allow users to stake JoeCoin", async function () {
      // Staking 100 JoeCoin
      const stakeAmount =ethers.parseEther("100");

      // Expect the staking event to be emitted
      await expect(jgtStaking.connect(userOne).stake(stakeAmount))
                                          .to.emit(jgtStaking, "Staked")
                                          .withArgs(userOne.address, stakeAmount);

      // Check the staking info
      const stakingInfo =await jgtStaking.stakingInfo(userOne.address);
      // Expect the staked amount to be equal to the stake amount from the info
      expect(stakingInfo.amount).to.equal(stakeAmount);
    });

    // Testing the staking of zero amount
    it("Should not allow staking zero amount", async function () {
      // Expect the staking to be reverted with the message "Cannot stake 0"
      await expect(jgtStaking.connect(userOne).stake(0)).to.be.revertedWith("Cannot stake 0");
    });
  });

  // Testing the rewards functionality
  describe("Rewards", function () {
    // Testing the accumulation of rewards over time
    it("Should accumulate rewards over time", async function () {
      // Staking 100 JoeCoin
      const stakeAmount =ethers.parseEther("100");
      await jgtStaking.connect(userOne).stake(stakeAmount);

      // Simulate one day passing 
      await network.provider.send("evm_increaseTime", [oneDay]);
      // Mine a new block to update the state
      await network.provider.send("evm_mine");

      // Calculate the reward for the user
      const pendingReward =await jgtStaking.calculateReward(userOne.address);
      // Assert the reward to be greater than 0
      expect(pendingReward).to.be.gt(0);
    });

    // Testing the claiming of rewards
    it("Should allow users to claim rewards", async function () {
      // Staking 100 JoeCoin
      const stakeAmount =ethers.parseEther("100");
      await jgtStaking.connect(userOne).stake(stakeAmount);

      // Simulate one day passing 
      await network.provider.send("evm_increaseTime", [oneDay]);
      // Mine a new block to update the state
      await network.provider.send("evm_mine");

      // Expect the reward claimed event to be emitted
      await expect(jgtStaking.connect(userOne).claimReward())
                                              .to.emit(jgtStaking, "RewardClaimed");
    });
  });

  // Testing the withdrawal functionality
  describe("Withdrawal", function () {
    // Testing the withdrawal of staked tokens
    it("Should allow users to withdraw staked tokens", async function () {
      // Staking 100 JoeCoin
      const stakeAmount =ethers.parseEther("100");
      await jgtStaking.connect(userOne).stake(stakeAmount);

      // Expect the withdrawal event to be emitted
      await expect(jgtStaking.connect(userOne).withdraw(stakeAmount))
                                              .to.emit(jgtStaking, "Withdrawn")
                                              .withArgs(userOne.address, stakeAmount);

      // Getting the staking info for the user after withdrawal
      const stakingInfo =await jgtStaking.stakingInfo(userOne.address);
      // Expect the staked amount to be 0
      expect(stakingInfo.amount).to.equal(0);
    });

    // Testing the withdrawal of more than the staked amount
    it("Should not allow withdrawing more than staked amount", async function () {
      // Staking 100 JoeCoin
      const stakeAmount =ethers.parseEther("100");
      await jgtStaking.connect(userOne).stake(stakeAmount);

      // Expect the withdrawal of more than staked to be reverted with the message "Insufficient balance"
      await expect(jgtStaking.connect(userOne).withdraw(ethers.parseEther("101")))
                                              .to.be.revertedWith("Insufficient balance");
    });
  });

  // Testing the staking functionality with multiple users
  describe("Multiple Users Staking", function () {
    // Testing the distribution of rewards among multiple stakers
    it("Should distribute rewards proportionally among multiple stakers", async function () {
      const stakeAmountUserOne =ethers.parseEther("100");
      const stakeAmountuserTwo =ethers.parseEther("200");

      // UserOne stakes 100 JoeCoin
      await jgtStaking.connect(userOne).stake(stakeAmountUserOne);

      // Simulate one day passing
      await network.provider.send("evm_increaseTime", [oneDay]);
      // Mine a new block to update the state
      await network.provider.send("evm_mine");

      // UserTwo stakes 200 JoeCoin
      await jgtStaking.connect(userTwo).stake(stakeAmountuserTwo);

      // Simulate one more day passing
      await network.provider.send("evm_increaseTime", [oneDay]);
      await network.provider.send("evm_mine");

      // Check rewards for both users
      const pendingRewardUser =await jgtStaking.calculateReward(userOne.address);
      const pendingRewarduserTwo =await jgtStaking.calculateReward(userTwo.address);

      // UserOne earns 100 first day (only contributor to the LP) and 33 the second day
      expect(pendingRewardUser).to.be.gt(ethers.parseEther("133")); 
      // UserTwo earns 66 the second day since he staked 200 and total in the LP is 300 on the 2nd day
      expect(pendingRewarduserTwo).to.be.gt(ethers.parseEther("66")); 
    });
  });

  // Testing the governance functions
  describe("Governance Functions", function () {
    // Testing the setting of reward rate
    it("Should allow only the owner to set reward rate", async function () {
      // Set the new reward rate
      const newRewardRate =ethers.parseEther("200");
  
      // Expect an error if a non-owner attempts to set the reward rate
      await expect(jgtStaking.connect(userOne).setRewardRate(newRewardRate))
                                              .to.be.revertedWithCustomError(jgtStaking, "OwnableUnauthorizedAccount")
                                              .withArgs(userOne.address); // Unauthorized account for verification
  
      // Expect the owner to be able to successfully call setRewardRate
      await expect(jgtStaking.connect(owner).setRewardRate(newRewardRate))
                                             .to.not.be.reverted;
    });
  });
  


  // Testing the adjustment of rewards after partial withdrawal
  it("Should correctly adjust rewards after partial withdrawal", async function () {
    const stakeAmount =ethers.parseEther("200");

    // User stakes 200 JoeCoin
    await jgtStaking.connect(userOne).stake(stakeAmount);

    // Simulate one day passing 
    await network.provider.send("evm_increaseTime", [oneDay]);
    await network.provider.send("evm_mine");

    // User withdraws half of their stake
    const withdrawalAmount =ethers.parseEther("100");
    await expect(jgtStaking.connect(userOne).withdraw(withdrawalAmount))
                                            .to.emit(jgtStaking, "Withdrawn")
                                            .withArgs(userOne.address, withdrawalAmount);

    // Check the remaining stake
    const stakingInfo =await jgtStaking.stakingInfo(userOne.address);
    expect(stakingInfo.amount).to.equal(ethers.parseEther("100"));

    // Simulate more time passing (1 day)
    await network.provider.send("evm_increaseTime", [oneDay]);
    await network.provider.send("evm_mine");

    // User claims rewards
    const pendingReward =await jgtStaking.calculateReward(userOne.address);
    expect(pendingReward).to.be.gt(ethers.parseEther("50")); // Rewards for remaining stake

    await jgtStaking.connect(userOne).claimReward();

    const userBalance =await jgtToken.balanceOf(userOne.address);
    expect(userBalance).to.be.gt(ethers.parseEther("150")); // Total rewards claimed
  });
});

// Testing the JoeCoinRBS contract
describe("JoeCoinRBS", function () {
  let rbs, owner, governance, addr1, addr2, oracle
  const ONE_HOUR = 3600;
  const BUFFER = 60; // 1 minute buffer
  const PRICE = ethers.parseEther("1"); // 1 USD price

  // Initial parameter values
  const initialParams = {
      C0: "10000000000000000",      // 0.01 ether
      W0: "20000000000000000",      // 0.02 ether
      alpha: "500000000000000000",  // 0.5 ether
      beta: "500000000000000000",   // 0.5 ether
      gamma: "100000000000000000"   // 0.1 ether 
  };

  // Helper function to advance time and mine a block
  async function advanceTimeAndBlock(time) {
      await network.provider.send("evm_increaseTime", [time]);
      await network.provider.send("evm_mine");
  }

  beforeEach(async function () {
      [owner, governance, addr1, addr2] = await ethers.getSigners();

      // Deploying mock oracle first
      const MockOracle = await ethers.getContractFactory("JoeCoinPriceOracle");
      oracle = await MockOracle.deploy();

      // Deploying RBS contract
      const RBS = await ethers.getContractFactory("JoeCoinRBS");
      rbs = await RBS.deploy(
          initialParams.C0,
          initialParams.W0,
          initialParams.alpha,
          initialParams.beta,
          initialParams.gamma,
          await oracle.getAddress()
      );

      await rbs.setGovernance(governance.address);
  });

  // Testing the Risk Calculations for RBS
  describe("Risk Calculations", function () {
    // Testing the update of baseline values
    it("Should calculate risk score correctly", async function () {
      // Start with base price
      await oracle.setPrice(owner.address, PRICE);
      await advanceTimeAndBlock(ONE_HOUR + BUFFER); // Advance enough time to update price
      await oracle.updatePrice();
    
      // Set second price after sufficient time
      await advanceTimeAndBlock(ONE_HOUR + BUFFER); // Ensure oracle allows price update
      await oracle.setPrice(owner.address, PRICE * 101n / 100n); // 1% increase
      await oracle.updatePrice();
    
      // Set third price
      await advanceTimeAndBlock(ONE_HOUR + BUFFER);
      await oracle.setPrice(owner.address, PRICE * 102n / 100n); // 2% total increase
      await oracle.updatePrice();
    
      // Set fourth price for sufficient data points
      await advanceTimeAndBlock(ONE_HOUR + BUFFER);
      await oracle.setPrice(owner.address, PRICE * 103n / 100n); // 3% total increase
      await oracle.updatePrice();
    
      // Set baseline values conservatively
      const baselineVals = {
        sentiment: ethers.parseEther("1"),     // 1.0
        volatility: ethers.parseEther("0.01"), // 1% volatility
        obi: ethers.parseEther("1"),           // 1.0
      };
    
      const currentVals = {
        sentiment: ethers.parseEther("0.99"),   // -1% change
        volatility: ethers.parseEther("0.012"), // 1.2% volatility
        obi: ethers.parseEther("0.99"),         // -1% change
      };
    
      // Update baseline and current values
      await rbs.updateBaselines(
        baselineVals.sentiment,
        baselineVals.volatility,
        baselineVals.obi
      );
    
      // Advance time to update current values
      await advanceTimeAndBlock(ONE_HOUR + BUFFER);
    
      await rbs.updateCurrentValues(
        currentVals.sentiment,
        currentVals.volatility,
        currentVals.obi
      );
    
      // Update risk factors
      await advanceTimeAndBlock(ONE_HOUR + BUFFER);
      await rbs.updateRiskFactors();
    
      // Calculate risk score
      const riskScore = await rbs.calculateRiskScore();
    
      // Verify results
      expect(riskScore).to.be.gt(0);
      expect(riskScore).to.be.lt(ethers.parseEther("1")); // Should be <100%
    });    
  });
});