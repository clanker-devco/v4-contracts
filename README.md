# v4.0.0-contracts

Smart contracts of Clanker v4.0.0

Clanker is an autonomous agent for deploying tokens. Currently, users may request clanker to deploy an ERC-20 token on Base by tagging [@clanker](https://farcaster.xyz/clanker/casts-and-replies) on Farcaster, on our website [clanker.world](https://www.clanker.world/deploy), by using one of our interface partners, or through the smart contracts directly. This repo contains the onchain code utilized by the clanker agent for token deployment, token pre-launch distribution, and LP fee management.

Documentation for the v4.0 contracts can be found [here](https://clanker.gitbook.io/clanker-documentation/references/core-contracts/v4.0.0) and our general docs can be found [here](https://clanker.gitbook.io/clanker-documentation).

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
- ClankerSniperAuctionV0: [0xFdc013ce003980889cFfd66b0c8329545ae1d1E8](https://basescan.org/address/0xFdc013ce003980889cFfd66b0c8329545ae1d1E8)
- ClankerSniperUtilV0: [0x4E35277306a83D00E13e8C8A4307C672FA31FC99](https://basescan.org/address/0x4E35277306a83D00E13e8C8A4307C672FA31FC99)
- ClankerLpLockerFeeConversion: [0x63D2DfEA64b3433F4071A98665bcD7Ca14d93496](https://basescan.org/address/0x63D2DfEA64b3433F4071A98665bcD7Ca14d93496)

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
- ClankerLpLockerFeeConversion: [0x824bB048a5EC6e06a09aEd115E9eEA4618DC2c8f](https://sepolia.basescan.org/address/0x824bB048a5EC6e06a09aEd115E9eEA4618DC2c8f)

### v4.0.0 (Unichain Mainnet)
- Clanker: [0xE85A59c628F7d27878ACeB4bf3b35733630083a9](https://uniscan.xyz/address/0xE85A59c628F7d27878ACeB4bf3b35733630083a9)
- ClankerFeeLocker: [0x1d5A0F0BD3eA07F78FC14577f053de7A3FEc35B2](https://uniscan.xyz/address/0x1d5A0F0BD3eA07F78FC14577f053de7A3FEc35B2)
- ClankerLpLockerFeeConversion: [0x691f97752E91feAcD7933F32a1FEdCeDae7bB59c](https://uniscan.xyz/address/0x691f97752E91feAcD7933F32a1FEdCeDae7bB59c)
- ClankerVault: [0xA9C0a423f0092176fC48d7B50a1fCae8cf5BB441](https://uniscan.xyz/address/0xA9C0a423f0092176fC48d7B50a1fCae8cf5BB441)
- ClankerAirdrop: [0x35bfE89d95F26674bF06bB8bFE55f8D73E9280D2](https://uniscan.xyz/address/0x35bfE89d95F26674bF06bB8bFE55f8D73E9280D2)
- ClankerUniv4EthDevBuy: [0x267259e36914839Eb584e962558563760AE28862](https://uniscan.xyz/address/0x267259e36914839Eb584e962558563760AE28862)
- ClankerMevBlockDelay: [0x42A95190B4088C88Dd904d930c79deC1158bF09D](https://uniscan.xyz/address/0x42A95190B4088C88Dd904d930c79deC1158bF09D)
- ClankerHookDynamicFee: [0x9b37A43422D7bBD4C8B231be11E50AD1acE828CC](https://uniscan.xyz/address/0x9b37A43422D7bBD4C8B231be11E50AD1acE828CC)
- ClankerHookStaticFee: [0xBc6e5aBDa425309c2534Bc2bC92562F5419ce8Cc](https://uniscan.xyz/address/0xBc6e5aBDa425309c2534Bc2bC92562F5419ce8Cc)
- ClankerSniperAuctionV0: [0x78B512C5074a1084bf3b8e6cbA8a1710d2a8d0A2](https://uniscan.xyz/address/0x78B512C5074a1084bf3b8e6cbA8a1710d2a8d0A2)
- ClankerSniperUtilV0: [0xA25e594869ddb46c33233A793E3c8b207CC719a2](https://uniscan.xyz/address/0xA25e594869ddb46c33233A793E3c8b207CC719a2)

### v4.0.0 (Arbitrum Mainnet)
- Clanker: [0xEb9D2A726Edffc887a574dC7f46b3a3638E8E44f](https://arbiscan.io/address/0xEb9D2A726Edffc887a574dC7f46b3a3638E8E44f)
- ClankerFeeLocker: [0x92C0DCbAba17b0F5f3a7537dA82c0F80520e4dF6](https://arbiscan.io/address/0x92C0DCbAba17b0F5f3a7537dA82c0F80520e4dF6)
- ClankerLpLockerFeeConversion: [0xF3622742b1E446D92e45E22923Ef11C2fcD55D68](https://arbiscan.io/address/0xF3622742b1E446D92e45E22923Ef11C2fcD55D68)
- ClankerVault: [0xa1da0600Eb4A9F3D4a892feAa2c2caf80A4A2f14](https://arbiscan.io/address/0xa1da0600Eb4A9F3D4a892feAa2c2caf80A4A2f14)
- ClankerAirdrop: [0x303470b6b6a35B06A5A05763A7caD776fbf27B71](https://arbiscan.io/address/0x303470b6b6a35B06A5A05763A7caD776fbf27B71)
- ClankerUniv4EthDevBuy: [0x70aDdc06fE89a5cF9E533aea8D025dB06795e492](https://arbiscan.io/address/0x70aDdc06fE89a5cF9E533aea8D025dB06795e492)
- ClankerMevTimeDelay: [0x4E35277306a83D00E13e8C8A4307C672FA31FC99](https://arbiscan.io/address/0x4E35277306a83D00E13e8C8A4307C672FA31FC99)
- ClankerHookDynamicFee: [0xFd213BE7883db36e1049dC42f5BD6A0ec66B68cC](https://arbiscan.io/address/0xFd213BE7883db36e1049dC42f5BD6A0ec66B68cC)
- ClankerHookStaticFee: [0xf7aC669593d2D9D01026Fa5B756DD5B4f7aAa8Cc](https://arbiscan.io/address/0xf7aC669593d2D9D01026Fa5B756DD5B4f7aAa8Cc)


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

Explanation of the parameters are in our [documentation](https://clanker.gitbook.io/clanker-documentation/references/core-contracts/v4.0.0). Please [reach out to us](https://clanker.gitbook.io/clanker-documentation/references/contact) if you have any questions! 
