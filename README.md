# v4.0.0-contracts

Smart contracts of Clanker v4.0.0

Clanker is an autonomous agent for deploying tokens. Currently, users may request clanker to deploy an ERC-20 token on Base by tagging [@clanker](https://farcaster.xyz/clanker/casts-and-replies) on Farcaster, on our website [clanker.world](https://www.clanker.world/deploy), by using one of our interface partners, or through the smart contracts directly. This repo contains the onchain code utilized by the clanker agent for token deployment, token pre-launch distribution, and LP fee management.

Documentation for the v4.0 contracts can be found [here](specs/v4_0_0.md) and our general docs can be found [here](https://clanker.gitbook.io/clanker-documentation) (note: not updated for v4.0 yet).

For a typescript sdk that interfaces with the clanker contracts, please see our companion repo [clanker-sdk](https://github.com/clanker-devco/clanker-sdk).


## Fee structure and rewards
As Clanker deploys tokens, it also creates dynamic fee Uniswap V4 pools using our custom hooks. Users are able to choose between static or dynamic fee pools. All user LP fees can be collected on the `ClankerFeeLocker` contract and can be managed on the `ClankerLpLocker` contract.

## Deployed Contracts

Check out our [dune dashboards](https://dune.com/clanker_protection_team) for token stats and our website [clanker.world](https://clanker.world) to see the clanker tokens in action and to launch a token.

### v4.0.0 (Base Mainnet)
- Clanker: [0xE85A59c628F7d27878ACeB4bf3b35733630083a9](https://basescan.org/address/0xE85A59c628F7d27878ACeB4bf3b35733630083a9)
- ClankerFeeLocker: [0xF3622742b1E446D92e45E22923Ef11C2fcD55D68](https://basescan.org/address/0xF3622742b1E446D92e45E22923Ef11C2fcD55D68)
- ClankerLpLocker: [0x29d17C1A8D851d7d4cA97FAe97AcAdb398D9cCE0](https://basescan.org/address/0x29d17C1A8D851d7d4cA97FAe97AcAdb398D9cCE0)
- ClankerVault: [0x8E845EAd15737bF71904A30BdDD3aEE76d6ADF6C](https://basescan.org/address/0x8E845EAd15737bF71904A30BdDD3aEE76d6ADF6C)
- ClankerAirdrop: [0x56Fa0Da89eD94822e46734e736d34Cab72dF344F](https://basescan.org/address/0x56Fa0Da89eD94822e46734e736d34Cab72dF344F)
- ClankerUniv4EthDevBuy: [0x1331f0788F9c08C8F38D52c7a1152250A9dE00be](https://basescan.org/address/0x1331f0788F9c08C8F38D52c7a1152250A9dE00be)
- ClankerMevBlockDelay: [0xE143f9872A33c955F23cF442BB4B1EFB3A7402A2](https://basescan.org/address/0xE143f9872A33c955F23cF442BB4B1EFB3A7402A2)
- ClankerHookDynamicFee: [0x34a45c6B61876d739400Bd71228CbcbD4F53E8cC](https://basescan.org/address/0x34a45c6B61876d739400Bd71228CbcbD4F53E8cC)
- ClankerHookStaticFee: [0xDd5EeaFf7BD481AD55Db083062b13a3cdf0A68CC](https://basescan.org/address/0xDd5EeaFf7BD481AD55Db083062b13a3cdf0A68CC)

### v4.0.0 (Base Sepolia)
- Clanker: [0xE85A59c628F7d27878ACeB4bf3b35733630083a9](https://sepolia.basescan.org/address/0xE85A59c628F7d27878ACeB4bf3b35733630083a9)
- ClankerFeeLocker: [0x42A95190B4088C88Dd904d930c79deC1158bF09D](https://sepolia.basescan.org/address/0x42A95190B4088C88Dd904d930c79deC1158bF09D)
- ClankerLpLockerMultiple: [0x33e2Eda238edcF470309b8c6D228986A1204c8f9](https://sepolia.basescan.org/address/0x33e2Eda238edcF470309b8c6D228986A1204c8f9)
- ClankerVault: [0xcC80d1226F899a78fC2E459a1500A13C373CE0A5](https://sepolia.basescan.org/address/0xcC80d1226F899a78fC2E459a1500A13C373CE0A5)
- ClankerAirdrop: [0x29d17C1A8D851d7d4cA97FAe97AcAdb398D9cCE0](https://sepolia.basescan.org/address/0x29d17C1A8D851d7d4cA97FAe97AcAdb398D9cCE0)
- ClankerUniv4EthDevBuy: [0x691f97752E91feAcD7933F32a1FEdCeDae7bB59c](https://sepolia.basescan.org/address/0x691f97752E91feAcD7933F32a1FEdCeDae7bB59c)
- ClankerMevBlockDelay: [0x71DB365E93e170ba3B053339A917c11024e7a9d4](https://sepolia.basescan.org/address/0x71DB365E93e170ba3B053339A917c11024e7a9d4)
- ClankerHookDynamicFee: [0xE63b0A59100698f379F9B577441A561bAF9828cc](https://sepolia.basescan.org/address/0xE63b0A59100698f379F9B577441A561bAF9828cc)
- ClankerHookStaticFee: [0xDFcCcfBeef7F3Fc8b16027Ce6feACb48024068cC](https://sepolia.basescan.org/address/0xDFcCcfBeef7F3Fc8b16027Ce6feACb48024068cC)
- ClankerSniperAuctionV0: [0x261fE99C4D0D41EE8d0e594D11aec740E8354ab0](https://sepolia.basescan.org/address/0x261fE99C4D0D41EE8d0e594D11aec740E8354ab0)
- ClankerSniperUtilV0: [0x8806169969aE96bfaaDb3eFd4B10785BEEb321b3](https://sepolia.basescan.org/address/0x8806169969aE96bfaaDb3eFd4B10785BEEb321b3)
- ClankerLpLockerFeeConversion: [0xD17cbd93993E0501Edb57097ae6F982Aceb4DB36](https://sepolia.basescan.org/address/0xD17cbd93993E0501Edb57097ae6F982Aceb4DB36)


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
