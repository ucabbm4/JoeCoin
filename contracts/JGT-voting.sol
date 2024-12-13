// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../libraries/ERC20.sol";
import "../libraries/ReentrancyGuard.sol";
import "../libraries/Ownable.sol";
import "./JGT-implementation.sol";

contract Governance is ReentrancyGuard, Ownable{
    JGTToken public immutable token;
     // Joe coin RBS reference in
    JoeCoinRBS public immutable rbs;

    struct Proposal {
        address proposer;
        string description;
        uint256 alpha;
        uint256 beta;  
        uint256 gamma;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 startTime;
        uint256 endTime;
        bool executed;
        mapping(address => bool) hasVoted;
    }

    struct ProposalInfo {
        address proposer;
        string description;
        uint256 alpha;
        uint256 beta;  
        uint256 gamma;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 startTime;
        uint256 endTime;
        bool executed;
    }

    uint256 public alpha; 
    uint256 public beta;  
    uint256 public gamma; 

    uint256 public proposalCount;
    mapping(uint256 => Proposal) public proposals;

    uint256 public constant VOTING_DELAY = 1 days;
    uint256 public constant VOTING_PERIOD = 3 days;
    uint256 public proposalCreationFee = 500 * 10**18; // Fee to deter spam 500 JGT

    bool public emergencyPaused = false;

    event ProposalCreated(
        uint256 indexed proposalId,
        address proposer,
        string description,
        uint256 alpha,
        uint256 beta,
        uint256 gamma,
        uint256 startTime,
        uint256 endTime
    );

    event Voted(
        uint256 indexed proposalId,
        address indexed voter,
        bool support,
        uint256 votes
    );

    event ProposalExecuted(
        uint256 indexed proposalId,
        uint256 alpha,
        uint256 beta,
        uint256 gamma
    );

    event ParametersUpdated(uint256 alpha, uint256 beta, uint256 gamma);

    event EmergencyPaused(bool paused);

    constructor(address _token, address _rbs) ReentrancyGuard() Ownable(msg.sender){
        token = JGTToken(_token);
        rbs = JoeCoinRBS(_rbs);

        alpha = 1e18; // Default alpha = 1
        beta = 1e18;  // Default beta = 1
        gamma = 5e16; // Default gamma = 0.05

        emit ParametersUpdated(alpha, beta, gamma);
    }

    // Function to calculate the proposal threshold 
    function getProposalThreshold() public view returns (uint256) {
    return (token.totalSupply() * 4) / 100; // 4% of total supply
    }

    // Function to propose a new set of RBS parameters
    function propose(
        string memory description,
        uint256 _alpha,
        uint256 _beta,
        uint256 _gamma
    ) external payable returns (uint256) {
        // Check if the proposer holds enough JGT to propose
        require(
            token.balanceOf(msg.sender) >= getProposalThreshold(),
            "Must have at least 4% of total JGT supply to propose"
        );
        // Check if the proposer has paid the proposal fee
        require(msg.value >= proposalCreationFee, "Insufficient fee");
        // Check if the new parameters are within the valid range
        require(_alpha >= 1e17 && _alpha <= 1e18, "Alpha must be between 0.1 and 1");
        require(_beta >= 1e17 && _beta <= 1e18, "Beta must be between 0.1 and 1");
        require(_gamma >= 5e16 && _gamma <= 5e17, "Gamma must be between 0.05 and 0.5");
        require(
            _alpha != alpha || _beta != beta || _gamma != gamma,
            "Proposal must change at least one parameter"
        );

        uint256 proposalId = proposalCount++;

        // Create a new proposal
        Proposal storage proposal = proposals[proposalId];

        proposal.proposer = msg.sender;
        proposal.description = description;
        proposal.alpha = _alpha;
        proposal.beta = _beta;
        proposal.gamma = _gamma;
        proposal.startTime = block.timestamp + VOTING_DELAY;
        proposal.endTime = proposal.startTime + VOTING_PERIOD;

        emit ProposalCreated(
            proposalId,
            msg.sender,
            description,
            _alpha,
            _beta,
            _gamma,
            proposal.startTime,
            proposal.endTime
        );

        return proposalId;
    }

    // Function to vote on a proposal
    function castVote(uint256 proposalId, bool support) external nonReentrant {
        // Check if voting is active
        require(canVote(proposalId), "Voting is not active");
        Proposal storage proposal = proposals[proposalId];
        // Check if the voter has not already voted
        require(!proposal.hasVoted[msg.sender], "Already voted");

        // Check if the voter has voting power
        uint256 votes = token.balanceOf(msg.sender);
        require(votes > 0, "Must have voting power");

        proposal.hasVoted[msg.sender] = true;

        if (support) {
            proposal.forVotes += votes;
        } else {
            proposal.againstVotes += votes;
        }

        emit Voted(proposalId, msg.sender, support, votes);
    }

    // Function to execute a proposal
    function executeProposal(uint256 proposalId) external nonReentrant {
        // Check if the emergency pause is not activated
        require(!emergencyPaused, "Emergency pause activated");
        // Check if the proposal is valid for exacution
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp > proposal.endTime, "Voting period not ended");
        require(block.timestamp <= proposal.endTime + 7 days, "Proposal expired");
        require(!proposal.executed, "Proposal already executed");
        require(isSucceeded(proposalId), "Proposal not succeeded");

        // based on the proposal, update the parameters of the RBS
        rbs.updateSensitivityParameters(
            proposal.alpha,
            proposal.beta,
            proposal.gamma
        );

        // Update contract state
        alpha = proposal.alpha;
        beta = proposal.beta;
        gamma = proposal.gamma;
    
        proposal.executed = true;

        emit ProposalExecuted(proposalId, alpha, beta, gamma);
        emit ParametersUpdated(alpha, beta, gamma);
    }

    // Reutrns the proposal details
    function getProposal(uint256 proposalId) external view returns (ProposalInfo memory) {
        Proposal storage proposal = proposals[proposalId];
        return ProposalInfo({
            proposer: proposal.proposer,
            description: proposal.description,
            alpha: proposal.alpha,
            beta: proposal.beta,
            gamma: proposal.gamma,
            forVotes: proposal.forVotes,
            againstVotes: proposal.againstVotes,
            startTime: proposal.startTime,
            endTime: proposal.endTime,
            executed: proposal.executed
        });
    }
    
    // Function to pause the contract in case of emergency
    function toggleEmergencyPause() external onlyOwner {
        emergencyPaused = !emergencyPaused;
        emit EmergencyPaused(emergencyPaused);
    }

    // Function to check if a proposal has succeeded
    function isSucceeded(uint256 proposalId) public view returns (bool) {
        Proposal storage proposal = proposals[proposalId];
        return proposal.forVotes > proposal.againstVotes &&
               proposal.forVotes > (token.totalSupply() * 10) / 100; // 10% quorum
    }

    // Function to check if a proposal is active to vote on
    function canVote(uint256 proposalId) public view returns (bool) {
        Proposal storage proposal = proposals[proposalId];
        return block.timestamp >= proposal.startTime &&
               block.timestamp <= proposal.endTime &&
               !proposal.executed;
    }

    // Function to update the proposal creation fee
    function updateProposalCreationFee(uint256 newFee) external onlyOwner {
        proposalCreationFee = newFee;
    }

    // Function to get the voting power of an account
    function getVotingPower(address account) external view returns (uint256) {
        return token.balanceOf(account);
    }
}

