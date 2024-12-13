const { expect } = require("chai");
const { ethers } = require("hardhat");

// Testing the JoeCoin, JoeCoinPriceOracle, JoeVault, and JoeCoinRBS contracts
describe("JoeCoin", function () {
  let joeCoin, JoeCoinPriceOracle, JoeVault, JoeCoinRBS;
  let joeCoinAddress, priceOracleAddress, vaultAddress, rbsAddress;
  let owner, governance, addr1, addr2;

  beforeEach(async function () {
    [owner, governance, addr1, addr2] = await ethers.getSigners();

    // Deploying JoeCoin contract
    const JoeCoinFactory = await ethers.getContractFactory("JoeCoin");
    joeCoin = await JoeCoinFactory.deploy();
    joeCoinAddress = await joeCoin.getAddress();

    // Deploying Price Oracle contract
    const PriceOracleFactory = await ethers.getContractFactory("JoeCoinPriceOracle");
    JoeCoinPriceOracle = await PriceOracleFactory.deploy();
    priceOracleAddress = await JoeCoinPriceOracle.getAddress();

    // Deploying RBS contract with initial parameters
    const RBSFactory = await ethers.getContractFactory("JoeCoinRBS");
    JoeCoinRBS = await RBSFactory.deploy(
        ethers.parseEther("0.01"), // C0 (1%) - Initial confidence parameter
        ethers.parseEther("0.02"), // W0 (2%) - Initial weight parameter
        ethers.parseEther("0.5"),  // alpha - Sentiment influence factor
        ethers.parseEther("0.5"),  // beta - Volatility influence factor
        ethers.parseEther("0.1"),  // gamma - OBI influence factor
        priceOracleAddress         // Price oracle address for market data
    );
    rbsAddress = await JoeCoinRBS.getAddress();

    // Deploying Vault contract
    const VaultFactory = await ethers.getContractFactory("JoeVault");
    JoeVault = await VaultFactory.deploy(joeCoinAddress, priceOracleAddress);
    vaultAddress = await JoeVault.getAddress();

    // Configuring initial contract settings
    await joeCoin.setGovernance(governance.address);
    await joeCoin.connect(governance).setPriceOracle(priceOracleAddress);
    await joeCoin.connect(governance).setStabilizer(rbsAddress);

    // Seting initial market price
    await JoeCoinPriceOracle.setPrice(joeCoinAddress, ethers.parseEther("1"));

    // Initialising RBS parameters
    await JoeCoinRBS.updateBaselines(
      ethers.parseEther("1"),   // baseline market sentiment
      ethers.parseEther("0.1"), // baseline market volatility
      ethers.parseEther("1")    // baseline order book imbalance
    );
  });

  // Testing the JoeCoin token functionality
  describe("JoeCoin", function () {
    // Testing the minting functionality under stable conditions
    it("should mint tokens when stabilization conditions are met", async function () {
      await joeCoin.connect(governance).toggleStabilization(true);
      const amount = ethers.parseEther("100");
      
      // Expect the mint to succeed when conditions are stable
      await joeCoin.connect(owner).mint(addr1.address, amount);
      expect(await joeCoin.balanceOf(addr1.address)).to.equal(amount);
    });

    // Testing the minting restrictions under unstable conditions
    it("should not mint tokens if stabilization conditions are not met", async function () {
      await joeCoin.connect(governance).toggleStabilization(true);
      
      // Simulate unstable market conditions
      await JoeCoinPriceOracle.setPrice(joeCoinAddress, ethers.parseEther("2")); 
      
      // Advance time to allow price update
      await ethers.provider.send("evm_increaseTime", [3600]);
      await ethers.provider.send("evm_mine");
      
      await JoeCoinRBS.updateRiskFactors();
      
      // Expect the mint to fail under unstable conditions
      const amount = ethers.parseEther("100");
      await expect(
        joeCoin.connect(owner).mint(addr1.address, amount)
      ).to.be.revertedWith("Stability conditions not met");
    });
  });

  // Testing the JoeVault functionality
  describe("JoeVault", function () {
    beforeEach(async function () {
      // Setup initial vault conditions
      await JoeVault.setCollateralSupport(joeCoinAddress, true);
      await joeCoin.connect(governance).toggleStabilization(false);
      await joeCoin.connect(owner).mint(addr1.address, ethers.parseEther("1000"));
    });

    // Testing vault creation and JoeCoin minting
    it("should create a JoeVault and mint JoeCoin", async function () {
      const collateralAmount = ethers.parseEther("100");
      const debtAmount = ethers.parseEther("50");

      // Setup vault permissions
      await joeCoin.transferOwnership(vaultAddress);
      await joeCoin.connect(addr1).approve(vaultAddress, collateralAmount);
      
      // Create new vault
      await JoeVault.connect(addr1).createVault(joeCoinAddress, collateralAmount, debtAmount);

      // Verify vault creation
      const vaultInfo = await JoeVault.vaults(addr1.address);
      expect(vaultInfo.collateralAmount).to.equal(collateralAmount);
      expect(vaultInfo.debtAmount).to.equal(debtAmount);
    });

    // Testing debt repayment and collateral withdrawal
    it("should allow debt repayment and collateral withdrawal", async function () {
      const collateralAmount = ethers.parseEther("100");
      const debtAmount = ethers.parseEther("50");
      const withdrawAmount = ethers.parseEther("50");
    
      // Setup initial balances and permissions
      await joeCoin.connect(owner).mint(addr1.address, ethers.parseEther("200"));
      await joeCoin.transferOwnership(vaultAddress);
      await joeCoin.connect(addr1).approve(vaultAddress, ethers.parseEther("1000"));
      
      // Create initial vault
      await JoeVault.connect(addr1).createVault(
        joeCoinAddress, 
        collateralAmount,
        debtAmount
      );
        
      // Repay debt and withdraw collateral
      await JoeVault.connect(addr1).repayDebt(
        joeCoinAddress,
        debtAmount,
        withdrawAmount
      );
    
      // Verify final vault state
      const updatedVaultInfo = await JoeVault.vaults(addr1.address);
      expect(updatedVaultInfo.debtAmount).to.equal(0n);
      expect(updatedVaultInfo.collateralAmount).to.equal(ethers.parseEther("50"));
    });
  });
});