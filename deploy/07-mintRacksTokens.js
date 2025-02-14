/* This Script is used to deploy RacksItems.sol contract into a TESTNET
     Deploy: 'yarn hardhat deploy --network mumbai'
    or 'yarn hardhat deploy --tags mintRacksToken --network mumbai' */
const { BigNumber } = require("ethers");
const { ethers } = require("hardhat");

module.exports = async ({ getNamedAccounts, deployments }) => {

    const racksTokenQuantity = 10000; //RacksTokens
    const decimals = 1000000000000000000n; // 10e18 
    const { deployer, user_1 } = await getNamedAccounts()
    const racksToken = await ethers.getContract("RacksToken", deployer)
    const racksTokenMintTx = await racksToken.mint(deployer, BigInt(racksTokenQuantity) * decimals, { gasLimit: 9999999 })
    console.log("Minting " + racksTokenQuantity + " RacksTokens to wallet: " + deployer);
    const racksTokenMintTxReceipt = await racksTokenMintTx.wait(1)
}

module.exports.tags = ["all", "mintRacksToken"]

