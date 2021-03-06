pragma solidity 0.4.23;


import "../math/SafeMath.sol";
import "../token/ERC20.sol";
import "./repository/FundRepository.sol";
import "./repository/ClaimRepository.sol";
import "../ownership/Owned.sol";
import "../token/ApproveAndCallFallback.sol";
import "../utils/strings.sol";
import "./validation/Precondition.sol";


/*
 * Main FundRequest Contract
 * Davy Van Roy
 * Quinten De Swaef
 */
contract FundRequestContract is Owned, ApproveAndCallFallBack {

    using SafeMath for uint256;
    using strings for *;

    event Funded(address indexed from, bytes32 platform, string platformId, address token, uint256 value);

    event Claimed(address indexed solverAddress, bytes32 platform, string platformId, string solver, address token, uint256 value);

    address public ETHER_ADDRESS = 0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee;

    //repositories
    FundRepository public fundRepository;

    ClaimRepository public claimRepository;

    address public claimSignerAddress;

    Precondition[] public preconditions;

    modifier addressNotNull(address target) {
        require(target != address(0), "target address can not be 0x0");
        _;
    }

    constructor(address _fundRepository, address _claimRepository) public {
        setFundRepository(_fundRepository);
        setClaimRepository(_claimRepository);
    }

    //entrypoints
    function fund(bytes32 _platform, string _platformId, address _token, uint256 _value) external returns (bool success) {
        require(doFunding(_platform, _platformId, _token, _value, msg.sender), "funding with token failed");
        return true;
    }

    function etherFund(bytes32 _platform, string _platformId) payable external returns (bool success) {
        require(doFunding(_platform, _platformId, ETHER_ADDRESS, msg.value, msg.sender), "funding with ether failed");
        return true;
    }

    function receiveApproval(address _from, uint _amount, address _token, bytes _data) public {
        var sliced = string(_data).toSlice();
        var platform = sliced.split("|AAC|".toSlice());
        var platformId = sliced.split("|AAC|".toSlice());
        require(doFunding(platform.toBytes32(), platformId.toString(), _token, _amount, _from));
    }

    function doFunding(bytes32 _platform, string _platformId, address _token, uint256 _value, address _funder) internal returns (bool success) {
        if(_token == ETHER_ADDRESS) {
            //must check this, so we don't have people foefeling with the amounts
            require(msg.value == _value);
        }
        require(!fundRepository.issueResolved(_platform, _platformId), "Can't fund tokens, platformId already claimed");
        for (uint idx = 0; idx < preconditions.length; idx++) {
            if (address(preconditions[idx]) != address(0)) {
                require(preconditions[idx].isValid(_platform, _platformId, _token, _value, _funder));
            }
        }
        require(_value > 0, "amount of tokens needs to be more than 0");

        if(_token != ETHER_ADDRESS) {
            require(ERC20(_token).transferFrom(_funder, address(this), _value), "Transfer of tokens to contract failed");
        }

        fundRepository.updateFunders(_funder, _platform, _platformId);
        fundRepository.updateBalances(_funder, _platform, _platformId, _token, _value);
        emit Funded(_funder, _platform, _platformId, _token, _value);
        return true;
    }

    function claim(bytes32 platform, string platformId, string solver, address solverAddress, bytes32 r, bytes32 s, uint8 v) public returns (bool) {
        require(validClaim(platform, platformId, solver, solverAddress, r, s, v), "Claimsignature was not valid");
        uint256 tokenCount = fundRepository.getFundedTokenCount(platform, platformId);
        for (uint i = 0; i < tokenCount; i++) {
            address token = fundRepository.getFundedTokensByIndex(platform, platformId, i);
            uint256 tokenAmount = fundRepository.claimToken(platform, platformId, token);
            if(token == ETHER_ADDRESS) {
                solverAddress.transfer(tokenAmount);
            } else {
                require(ERC20(token).transfer(solverAddress, tokenAmount), "transfer of tokens from contract failed");
            }
            require(claimRepository.addClaim(solverAddress, platform, platformId, solver, token, tokenAmount), "adding claim to repository failed");
            emit Claimed(solverAddress, platform, platformId, solver, token, tokenAmount);
        }
        require(fundRepository.finishResolveFund(platform, platformId), "Resolving the fund failed");
        return true;
    }

    function validClaim(bytes32 platform, string platformId, string solver, address solverAddress, bytes32 r, bytes32 s, uint8 v) internal view returns (bool) {
        bytes32 h = keccak256(createClaimMsg(platform, platformId, solver, solverAddress));
        address signerAddress = ecrecover(h, v, r, s);
        return claimSignerAddress == signerAddress;
    }

    function createClaimMsg(bytes32 platform, string platformId, string solver, address solverAddress) internal pure returns (string) {
        return strings.bytes32ToString(platform)
        .strConcat(prependUnderscore(platformId))
        .strConcat(prependUnderscore(solver))
        .strConcat(prependUnderscore(strings.addressToString(solverAddress)));
    }

    function addPrecondition(address _precondition) external onlyOwner {
        preconditions.push(Precondition(_precondition));
    }

    function removePrecondition(uint _index) external onlyOwner {
        delete preconditions[_index];
    }

    function setFundRepository(address _repositoryAddress) public onlyOwner {
        fundRepository = FundRepository(_repositoryAddress);
    }

    function setClaimRepository(address _claimRepository) public onlyOwner {
        claimRepository = ClaimRepository(_claimRepository);
    }

    function setClaimSignerAddress(address _claimSignerAddress) addressNotNull(_claimSignerAddress) public onlyOwner {
        claimSignerAddress = _claimSignerAddress;
    }

    function prependUnderscore(string str) internal pure returns (string) {
        return "_".strConcat(str);
    }

    //required to be able to migrate to a new FundRequestContract
    function migrateTokens(address _token, address newContract) external onlyOwner {
        require(newContract != address(0));
        if(_token == ETHER_ADDRESS) {
            newContract.transfer(address(this).balance);
        } else {
            ERC20 token = ERC20(_token);
            token.transfer(newContract, token.balanceOf(address(this)));
        }
    }

    //required should there be an issue with available ether
    function deposit() external onlyOwner payable {
        require(msg.value > 0, "Should at least be 1 wei deposited");
    }

    function() external {
        // dont receive ether via fallback
    }
}