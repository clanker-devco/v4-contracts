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
- Clanker: [0x41E02952482e5Aa2e649855155bFD72A446f424F](https://sepolia.basescan.org/address/0x41E02952482e5Aa2e649855155bFD72A446f424F)
- ClankerFeeLocker: [0x49a8896bA71990d8D1E0D82F4cB0563aBd51C228](https://sepolia.basescan.org/address/0x49a8896bA71990d8D1E0D82F4cB0563aBd51C228)
- ClankerLpLockerMultiple: [0x85cCe34e56DD838BF812B1aE8b1E5D2058a14e08](https://sepolia.basescan.org/address/0x85cCe34e56DD838BF812B1aE8b1E5D2058a14e08)
- ClankerVault: [0x20114919C35B520e7dA9a8d895DF0fe175e01f39](https://sepolia.basescan.org/address/0x20114919C35B520e7dA9a8d895DF0fe175e01f39)
- ClankerAirdrop: [0x6637082F78116ead3C57eD03D93B56405D0398aa](https://sepolia.basescan.org/address/0x6637082F78116ead3C57eD03D93B56405D0398aa)
- ClankerUniv4EthDevBuy: [0xFc88f3A73DE4007342cf46F4fc3914FF4e4A58BB](https://sepolia.basescan.org/address/0xFc88f3A73DE4007342cf46F4fc3914FF4e4A58BB)
- ClankerMevBlockDelay: [0xf2226f4fE61C7c62f112E9B244DbEB5918A4982C](https://sepolia.basescan.org/address/0xf2226f4fE61C7c62f112E9B244DbEB5918A4982C)
- ClankerHookDynamicFee: [0x9c9048D6C68B2d87f3Cc10A224A5504149E168cC](https://sepolia.basescan.org/address/0x9c9048D6C68B2d87f3Cc10A224A5504149E168cC)
- ClankerHookStaticFee: [0x3eC2a26b6eF16c288561692AE8D9681fa773A8cc](https://sepolia.basescan.org/address/0x3eC2a26b6eF16c288561692AE8D9681fa773A8cc)


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
// callable by anyone when the factory is not deprecated
function deployToken(DeploymentConfig memory deploymentConfig)
        external
        payable
        returns (address tokenAddress);



/**
* Configuration settings for token creation
*/

struct DeploymentConfig {
    TokenConfig tokenConfig;
    PoolConfig poolConfig;
    LockerConfig lockerConfig;
    MevModuleConfig mevModuleConfig;
    ExtensionConfig[] extensionConfigs;
}

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
    address locker;
    // reward info
    address[] rewardAdmins;
    address[] rewardRecipients;
    uint16[] rewardBps;
    // liquidity placement info
    int24[] tickLower;
    int24[] tickUpper;
    uint16[] positionBps;
    bytes lockerData;
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
```

Explanation of the parameters are in the [specs](specs/v4_0_0.md) folder. Please [reach out to us](https://clanker.gitbook.io/clanker-documentation/references/contact) if you have any questions! 