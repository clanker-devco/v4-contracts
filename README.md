# v4.0.0-contracts

Smart contracts of Clanker v4.0

Clanker is an autonomous agent for deploying tokens. Currently, users may request clanker to deploy an ERC-20 token on Base by tagging [@clanker](https://farcaster.xyz/clanker/casts-and-replies) on Farcaster, on our website [clanker.world](https://www.clanker.world/deploy), by using one of our interface partners, or through the smart contracts directly. This repo contains the onchain code utilized by the clanker agent for token deployment, token pre-launch distribution, and LP fee management.

Documentation for the v4.0 contracts can be found [here](specs/v4_0_0.md) and our general docs can be found [here](https://clanker.gitbook.io/clanker-documentation) (note: not updated for v4.0 yet).

For a typescript sdk that interfaces with the clanker contracts, please see our companion repo [clanker-sdk](https://github.com/clanker-devco/clanker-sdk).


## Fee structure and rewards
As Clanker deploys tokens, it also creates dynamic fee Uniswap V4 pools using our custom hooks. Users are able to choose between static or dynamic fee pools. All user LP fees can be collected on the `ClankerFeeLocker` contract and can be managed on the `ClankerLpLocker` contract.

## Deployed Contracts

Check out our [dune dashboards](https://dune.com/clanker_protection_team) for token stats and our website [clanker.world](https://clanker.world) to see the clanker tokens in action and to launch a token.

### v4.0.0 (Base Sepolia)
- Clanker: [0xeBA5bCE4a0e62e8D374fa46c6914D8d8c70619f6](https://sepolia.basescan.org/address/0xeBA5bCE4a0e62e8D374fa46c6914D8d8c70619f6)
- ClankerFeeLocker: [0x4c9977926000A6C9EbAa583f92f2730245846060](https://sepolia.basescan.org/address/0x4c9977926000A6C9EbAa583f92f2730245846060)
- ClankerLpLockerMultiple: [0x94e85fBb6e86eE3bdCFd2b24F17f9d66B14D70f8](https://sepolia.basescan.org/address/0x94e85fBb6e86eE3bdCFd2b24F17f9d66B14D70f8)
- ClankerVault: [0xfed01720E35FA0977254414B7245f9b78D87c76b](https://sepolia.basescan.org/address/0xfed01720E35FA0977254414B7245f9b78D87c76b)
- ClankerAirdrop: [0xB68f58460B7a80Bd8232F5A714b3899F8B43dE04](https://sepolia.basescan.org/address/0xB68f58460B7a80Bd8232F5A714b3899F8B43dE04)
- ClankerUniv4EthDevBuy: [0x685DfF86292744500E624c629E91E20dd68D9908](https://sepolia.basescan.org/address/0x685DfF86292744500E624c629E91E20dd68D9908)
- ClankerMevBlockDelay: [0x9037603A27aCf7c70A2A531B60cCc48eCD154fB3](https://sepolia.basescan.org/address/0x9037603A27aCf7c70A2A531B60cCc48eCD154fB3)
- ClankerHookDynamicFee: [0x03c8FDe0d02D1f42B73127D9EC18A5a48853a8cC](https://sepolia.basescan.org/address/0x03c8FDe0d02D1f42B73127D9EC18A5a48853a8cC)
- ClankerHookStaticFee: [0x3227d5AA27FC55AB4d4f8A9733959B265aBDa8cC](https://sepolia.basescan.org/address/0x3227d5AA27FC55AB4d4f8A9733959B265aBDa8cC)


If you'd like these contracts on another chain, [please reach out to us](https://clanker.gitbook.io/clanker-documentation/references/contact)! For superchain purposes, we need to ensure that the Clanker contracts have the same address.


## Usage

Token deployers should use the `Clanker::deployToken()` function to deploy tokens. Deployers are able to configure the deployments in a variety of ways, including:
- Sending portions of the token supply to a vault or airdrop via `Extensions`
- Splitting the LP rewards between multiple recipients
- Specifying multiple initial liquidity positions with custom tick ranges
- Performing devBuys from the pool during token launch
- Choosing between 



Note that the follow parameters are needed for deployment:
```solidity
/**
* Configuration settings for token creation
*/

struct TokenConfig {
    address tokenAdmin;
    string name;
    string symbol;
    bytes32 salt;
    string image;
    string metadata;
    string context;
    uint256 originatingChainId;
}

struct PoolConfig {
    address hook;
    address pairedToken;
    int24 tickIfToken0IsClanker;
    int24 tickSpacing;
    bytes poolData;
}

struct LockerConfig {
    // reward info
    address[] rewardAdmins;
    address[] rewardRecipients;
    uint16[] rewardBps;
    // liquidity placement info
    int24[] tickLower;
    int24[] tickUpper;
    uint16[] positionBps;
}

struct ExtensionConfig {
    address extension;
    uint256 msgValue;
    uint16 extensionBps;
    bytes extensionData;
}

struct MevModuleConfig {
    address mevModule;
    bytes mevModuleData;
}

struct DeploymentConfig {
    TokenConfig tokenConfig;
    PoolConfig poolConfig;
    LockerConfig lockerConfig;
    MevModuleConfig mevModuleConfig;
    ExtensionConfig[] extensionConfigs;
}

// callable by anyone when the factory is not deprecated
function deployToken(DeploymentConfig memory deploymentConfig)
        external
        payable
        returns (address tokenAddress);
```

Explanation of the parameters are in the [specs](specs/v4_0_0.md) folder. Please [reach out to us](https://clanker.gitbook.io/clanker-documentation/references/contact) if you have any questions! 