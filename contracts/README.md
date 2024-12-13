# JoeCoin
comp0163 coursework

This code utilizes OpenZeppelin's open source ERC20 implementation. OpenZeppelin is a widely-used library that already has the base functions we want to inherit from.  I've copied the required files locally so he implementation works without internet access.

JoeCoin (JOE): ERC20 stablecoin
JoeVault: Manages collateralized lending
PriceOracle: Provides price feeds for collateral

Current Features:

Deposit approved collateral tokens
Mint JoeCoin against their collateral (minimum 150% collateralization)
Repay debt to retrieve collateral
Get liquidated if collateral ratio drops below 130%
Configurable collateral ratios
Support for multiple collateral types

Parameters:
0.5% annual stability fee
13% liquidation penalty


Joe's Governence Tool(JGT): ERC20 token
JGT Token: Governance token with 1M initial supply
Staking Contract: Rewards JOE stakers with JGT
Liquidity Mining: Rewards LP providers with JGT
Governance Contract: Handles voting and proposals

Current Features:
Basic staking: 100 JGT/day for staking JOE
Liquidity mining: 200 JGT/day for providing liquidity


Voting Mechanism:
Proposal creation requires 100,000 JGT
1-day voting delay, 3-day voting period
10% quorum requirement
One token = one vote



How it works:
Deploy JoeCoin and JoeVault
Deploy JGT token and governance system
Set up reward rates and parameters


User Interactions:
Users can deposit collateral to mint JOE
JOE can be staked for JGT rewards
JOE can be provided as liquidity for higher JGT rewards
JGT holders can propose changes
Community votes on proposals
Successful proposals can be executed

