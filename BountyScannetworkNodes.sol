// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract NetworkNodeBounty {
    struct Bounty {
        address creator;
        uint256 systemId;
        string systemName;
        uint256 amount;
        uint256 createdAt;
        bool claimed;
        address claimedBy;
        address[] excludedAddresses; // Addresses that had NetworkNodes when bounty was created
    }
    
    // State variables
    mapping(uint256 => Bounty) public bounties;
    mapping(uint256 => uint256[]) public bountiesOnSystem; // systemId => bountyIds
    mapping(string => uint256) public systemNameToId; // systemName => systemId for lookup
    uint256 public bountyCounter;
    address public owner;
    
    // Events
    event BountyCreated(
        uint256 indexed bountyId, 
        uint256 indexed systemId, 
        string systemName, 
        address indexed creator, 
        uint256 amount,
        address[] excludedAddresses
    );
    event BountyClaimed(uint256 indexed bountyId, address indexed claimer, uint256 systemId);
    event BountyCancelled(uint256 indexed bountyId);
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    constructor() {
        owner = msg.sender;
    }
    
    // Create a new bounty for NetworkNode placement in a specific solar system
    function createBounty(
        uint256 _systemId,
        string memory _systemName,
        address[] memory _existingNetworkNodeOwners
    ) external payable {
        require(msg.value > 0, "Bounty amount must be greater than 0");
        require(_systemId > 0, "Invalid system ID");
        require(bytes(_systemName).length > 0, "System name cannot be empty");
        
        uint256 bountyId = bountyCounter++;
        
        bounties[bountyId] = Bounty({
            creator: msg.sender,
            systemId: _systemId,
            systemName: _systemName,
            amount: msg.value,
            createdAt: block.timestamp,
            claimed: false,
            claimedBy: address(0),
            excludedAddresses: _existingNetworkNodeOwners
        });
        
        bountiesOnSystem[_systemId].push(bountyId);
        systemNameToId[_systemName] = _systemId;
        
        emit BountyCreated(bountyId, _systemId, _systemName, msg.sender, msg.value, _existingNetworkNodeOwners);
    }
    
    // Claim a bounty by proving NetworkNode placement
    function claimBounty(uint256 _bountyId) external {
        Bounty storage bounty = bounties[_bountyId];
        
        // Basic validations
        require(!bounty.claimed, "Bounty already claimed");
        require(bounty.amount > 0, "Bounty does not exist");
        
        // Check if claimant was excluded (had NetworkNode when bounty was created)
        require(!_isAddressExcluded(bounty.excludedAddresses, msg.sender), 
                "Address had NetworkNode in system when bounty was created");
        
        // Mark as claimed
        bounty.claimed = true;
        bounty.claimedBy = msg.sender;
        
        // Transfer the bounty amount to the claimant
        (bool success, ) = payable(msg.sender).call{value: bounty.amount}("");
        require(success, "Transfer failed");
        
        emit BountyClaimed(_bountyId, msg.sender, bounty.systemId);
    }
    
    // Cancel an unclaimed bounty (only by creator)
    function cancelBounty(uint256 _bountyId) external {
        Bounty storage bounty = bounties[_bountyId];
        
        require(bounty.creator == msg.sender, "Only creator can cancel bounty");
        require(!bounty.claimed, "Cannot cancel claimed bounty");
        require(bounty.amount > 0, "Bounty does not exist");
        
        uint256 refundAmount = bounty.amount;
        bounty.amount = 0;
        bounty.claimed = true; // Prevent re-entrancy
        
        (bool success, ) = payable(msg.sender).call{value: refundAmount}("");
        require(success, "Refund failed");
        
        emit BountyCancelled(_bountyId);
    }
    
    // Helper function to check if address is in excluded list
    function _isAddressExcluded(address[] memory excludedAddresses, address checkAddress) 
        internal 
        pure 
        returns (bool) 
    {
        for (uint256 i = 0; i < excludedAddresses.length; i++) {
            if (excludedAddresses[i] == checkAddress) {
                return true;
            }
        }
        return false;
    }
    
    // Get all bounty IDs for a solar system
    function getBountiesOnSystem(uint256 _systemId) external view returns (uint256[] memory) {
        return bountiesOnSystem[_systemId];
    }
    
    // Get active (unclaimed) bounties for a solar system
    function getActiveBountiesOnSystem(uint256 _systemId) external view returns (uint256[] memory) {
        uint256[] memory allBounties = bountiesOnSystem[_systemId];
        uint256 activeCount = 0;
        
        // Count active bounties
        for (uint256 i = 0; i < allBounties.length; i++) {
            if (!bounties[allBounties[i]].claimed) {
                activeCount++;
            }
        }
        
        // Create array of active bounties
        uint256[] memory activeBounties = new uint256[](activeCount);
        uint256 currentIndex = 0;
        
        for (uint256 i = 0; i < allBounties.length; i++) {
            if (!bounties[allBounties[i]].claimed) {
                activeBounties[currentIndex] = allBounties[i];
                currentIndex++;
            }
        }
        
        return activeBounties;
    }
    
    // Get total active bounty value for a solar system
    function getTotalBountyOnSystem(uint256 _systemId) external view returns (uint256) {
        uint256[] memory allBounties = bountiesOnSystem[_systemId];
        uint256 totalValue = 0;
        
        for (uint256 i = 0; i < allBounties.length; i++) {
            if (!bounties[allBounties[i]].claimed) {
                totalValue += bounties[allBounties[i]].amount;
            }
        }
        
        return totalValue;
    }
    
    // Get system ID by system name
    function getSystemIdByName(string memory _systemName) external view returns (uint256) {
        return systemNameToId[_systemName];
    }
    
    // Get excluded addresses for a bounty
    function getBountyExcludedAddresses(uint256 _bountyId) external view returns (address[] memory) {
        return bounties[_bountyId].excludedAddresses;
    }
    
    // Check if an address can claim a specific bounty
    function canAddressClaimBounty(uint256 _bountyId, address _address) external view returns (bool) {
        Bounty storage bounty = bounties[_bountyId];
        
        if (bounty.claimed || bounty.amount == 0) {
            return false;
        }
        
        return !_isAddressExcluded(bounty.excludedAddresses, _address);
    }
    
    // Emergency withdrawal (only owner, only if something goes wrong)
    function emergencyWithdraw() external onlyOwner {
        (bool success, ) = payable(owner).call{value: address(this).balance}("");
        require(success, "Withdrawal failed");
    }
}
