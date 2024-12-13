const { expect } = require("chai");
const { ethers, network } = require("hardhat");

// Test suite for Governance contract
describe("Governance Contract", function () {
  let owner, proposer, voter1, voter2, voter3;
  let jgtToken, rbs, governance, oracle;
  const oneDay = 24 * 60 * 60;

  beforeEach(async function () {
    [owner, proposer, voter1, voter2, voter3] = await ethers.getSigners();

    // Deploying JGTToken
    const JGTToken = await ethers.getContractFactory("JGTToken");
    jgtToken = await JGTToken.deploy();
    const jgtTokenAddress = await jgtToken.getAddress();

    // Deploying Oracle
    const JoeCoinPriceOracle = await ethers.getContractFactory("JoeCoinPriceOracle");
    oracle = await JoeCoinPriceOracle.deploy();
    const oracleAddress = await oracle.getAddress();

    // Deploying RBS
    const JoeCoinRBS = await ethers.getContractFactory("JoeCoinRBS");
    rbs = await JoeCoinRBS.deploy(
      ethers.parseEther("0.01"),    // _C0 (1% cushion)
      ethers.parseEther("0.02"),    // _W0 (2% wall)
      ethers.parseEther("0.5"),     // _alpha (0.01 to 0.1 range)
      ethers.parseEther("0.5"),     // _beta  (0.01 to 0.1 range)
      ethers.parseEther("0.05"),    // _gamma (0.05 to 0.5 range)
      oracleAddress                 // _oracle address
    );

    // Getting the address of the deployed RBS contract
    const rbsAddress = await rbs.getAddress();

    // Deploy Governance
    const Governance = await ethers.getContractFactory("Governance");
    governance = await Governance.deploy(jgtTokenAddress, rbsAddress);
    const governanceAddress = await governance.getAddress();

    // Set governance address in RBS
    await rbs.connect(owner).setGovernance(governanceAddress);

    // Mint and distribute tokens
    const totalSupply = ethers.parseEther("1000000");
    await jgtToken.transfer(proposer.address, ethers.parseEther("200000"));
    await jgtToken.transfer(voter1.address, ethers.parseEther("150000"));
    await jgtToken.transfer(voter2.address, ethers.parseEther("100000"));
    await jgtToken.transfer(voter3.address, ethers.parseEther("50000"));

    // Approve governance contract
    await jgtToken.connect(proposer).approve(governanceAddress, totalSupply);
    await jgtToken.connect(voter1).approve(governanceAddress, totalSupply);
    await jgtToken.connect(voter2).approve(governanceAddress, totalSupply);
    await jgtToken.connect(voter3).approve(governanceAddress, totalSupply);
  });

  // Testing the proposal creation functionality
  describe("Proposal Creation", function () {
    // Test case for a valid proposal
    it("Should allow a valid proposal", async function () {
      const alpha = ethers.parseEther("0.5");  
      const beta = ethers.parseEther("0.5");   
      const gamma = ethers.parseEther("0.1");   
      const description = "Change parameters to improve governance.";
      const creationFee = await governance.proposalCreationFee();

      // Propose a new proposal
      const tx = await governance.connect(proposer).propose(
        description, 
        alpha, 
        beta, 
        gamma, 
        { value: creationFee }
      );
      await tx.wait();

      const proposal = await governance.getProposal(0);

      // Verify the proposal details
      expect(proposal.proposer).to.equal(proposer.address);
      expect(proposal.description).to.equal(description);
      expect(proposal.alpha).to.equal(alpha);
      expect(proposal.beta).to.equal(beta);
      expect(proposal.gamma).to.equal(gamma);
    });

    // Test case for invalid proposal parameters
    it("Should not allow proposal with invalid parameters", async function () {
      const invalidAlpha = ethers.parseEther("0.005"); // Below MIN_ALPHA_BETA
      const beta = ethers.parseEther("0.5");
      const gamma = ethers.parseEther("0.1");
      const creationFee = await governance.proposalCreationFee();

      // Propose a new proposal with invalid alpha
      // Expect the proposal to be reverted
      await expect(
        governance.connect(proposer).propose(
          "Invalid params",
          invalidAlpha,
          beta,
          gamma,
          { value: creationFee }
        )
      ).to.be.revertedWith("Alpha must be between 0.1 and 1");
    });
  });

  // Testing the voting functionality
  describe("Voting", function () {
    beforeEach(async function () {
      const alpha = ethers.parseEther("0.5");  
      const beta = ethers.parseEther("0.5");   
      const gamma = ethers.parseEther("0.1");   
      const creationFee = await governance.proposalCreationFee();

      // Propose a new proposal
      await governance.connect(proposer).propose(
        "Vote on this!", 
        alpha, 
        beta, 
        gamma, 
        { value: creationFee }
      );

      // Advance time to allow voting
      await network.provider.send("evm_increaseTime", [oneDay]); 
      await network.provider.send("evm_mine");
    });

    // Test case for voting on a proposal
    it("Should allow voting for a proposal", async function () {
      const votes = await jgtToken.balanceOf(voter1.address);
      // Voter1 votes in favor
      await expect(governance.connect(voter1).castVote(0, true))
        .to.emit(governance, "Voted")
        .withArgs(0, voter1.address, true, votes);

      // Verify the vote count
      const proposal = await governance.getProposal(0);
      expect(proposal.forVotes).to.equal(votes);
    });

    // Test case for double voting
    it("Should not allow double voting", async function () {
      // Voter1 votes in favor AGAIN
      await governance.connect(voter1).castVote(0, true);
      // Expect the vote to be reverted
      await expect(
        governance.connect(voter1).castVote(0, false)
      ).to.be.revertedWith("Already voted");
    });

    // Test case for voting after voting time expiration
    it("Should not allow voting if voting period is inactive", async function () {
      // Advance time to end voting period
      await network.provider.send("evm_increaseTime", [4 * oneDay]); 
      await network.provider.send("evm_mine");

      // Expect the vote to be reverted
      await expect(governance.connect(voter1).castVote(0, true)).to.be.revertedWith("Voting is not active");
    });
  });

  // Testing the proposal execution functionality
  describe("Proposal Execution", function () {
    beforeEach(async function () {
      const alpha = ethers.parseEther("0.5");  
      const beta = ethers.parseEther("0.5");   
      const gamma = ethers.parseEther("0.1");   
      const creationFee = await governance.proposalCreationFee();
      
      // Propose a new proposal
      await governance.connect(proposer).propose(
        "Execute this proposal!", 
        alpha, 
        beta, 
        gamma, 
        { value: creationFee }
      );

      // Advance time to allow voting
      await network.provider.send("evm_increaseTime", [oneDay]); 
      await network.provider.send("evm_mine");
    });

    // Test case for successful proposal execution
    it("Should execute a successful proposal", async function () {
      // Get the proposal before execution
      const proposalBefore = await governance.getProposal(0);
      
      // Voter1 and Voter2 vote in favor (250,000 tokens > 10% of total supply)
      await governance.connect(voter1).castVote(0, true);
      await governance.connect(voter2).castVote(0, true);
      
      // Advance time to end voting period
      await network.provider.send("evm_increaseTime", [3 * oneDay]);
      await network.provider.send("evm_mine");

      // Execute the proposal and verify the event
      await expect(governance.executeProposal(0))
                            .to.emit(governance, "ProposalExecuted")
                            .withArgs(0, proposalBefore.alpha, proposalBefore.beta, proposalBefore.gamma);
    });


    // Test case for unsuccessful proposal execution
    it("Should not execute an unsuccessful proposal", async function () {
      // Only voter1 votes in favor (150,000 tokens)
      await governance.connect(voter1).castVote(0, true);
      
      // voter2 and voter3 vote against (150,000 tokens total)
      await governance.connect(voter2).castVote(0, false);
      await governance.connect(voter3).castVote(0, false);

      // Advance time to end voting
      await network.provider.send("evm_increaseTime", [3 * oneDay]);
      await network.provider.send("evm_mine");

      // Expect the proposal to be reverted as the threashold for votes wasn't met
      await expect(governance.executeProposal(0)).to.be.revertedWith("Proposal not succeeded");
    });

    // Test case for expired proposal execution
    it("Should not execute an expired proposal", async function () {
      // Advance time to end to proposal expiration
      await network.provider.send("evm_increaseTime", [13 * oneDay]); 
      await network.provider.send("evm_mine");

      // Expect the proposal to be reverted as it has expired
      await expect(governance.executeProposal(0)).to.be.revertedWith("Proposal expired");
    });
  });

  // Testing the emergency pause functionality
  describe("Emergency Pause", function () {
    // Test case for emergency pause
    it("Should allow owner to toggle emergency pause", async function () {
      await expect(governance.toggleEmergencyPause())
                              .to.emit(governance, "EmergencyPaused")
                              .withArgs(true);

      // Verify the emergency pause status
      expect(await governance.emergencyPaused()).to.be.true;
      
      // Disable emergency pause
      await governance.toggleEmergencyPause();
      // Verify the emergency pause status
      expect(await governance.emergencyPaused()).to.be.false;
    });

    // Test case for proposal execution during emergency pause
    it("Should prevent proposal execution during emergency pause", async function () {
      // Toggle emergency pause
      await governance.toggleEmergencyPause();
      
      // Expect the proposal execution to be reverted
      await expect(governance.executeProposal(0)).to.be.revertedWith("Emergency pause activated");
    });
  });
});