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
    }

    // Platform fee configuration
    address public constant PLATFORM_FEE_ADDRESS = 0xEf57543E620bA2229382351619580ACA32Ae0a62;
    uint256 public constant PLATFORM_FEE_PERCENTAGE = 10; // 10%

    mapping(uint256 => Bounty) public bounties;
    mapping(uint256 => address[]) public bountyExcludedAddresses;
    mapping(uint256 => uint256[]) public systemBounties;
    
    uint256 public bountyCounter;

    event BountyCreated(
        uint256 indexed bountyId,
        uint256 indexed systemId,
        string systemName,
        address indexed creator,
        uint256 amount,
        address[] excludedAddresses
    );

    event BountyClaimed(
        uint256 indexed bountyId,
        address indexed claimer,
        uint256 systemId
    );

    event BountyCancelled(uint256 indexed bountyId);

    event PlatformFeeTransferred(
        uint256 indexed bountyId,
        address indexed feeRecipient,
        uint256 feeAmount
    );

    modifier onlyBountyCreator(uint256 _bountyId) {
        require(bounties[_bountyId].creator == msg.sender, "Not bounty creator");
        _;
    }

    modifier bountyExists(uint256 _bountyId) {
        require(_bountyId < bountyCounter, "Bounty does not exist");
        _;
    }

    modifier bountyNotClaimed(uint256 _bountyId) {
        require(!bounties[_bountyId].claimed, "Bounty already claimed");
        _;
    }

    /**
     * @dev Create a new bounty for a solar system
     * @param _systemId The EVE Online solar system ID
     * @param _systemName The name of the solar system
     * @param _existingNetworkNodeOwners Array of addresses that already own NetworkNodes in this system
     * 
     * The function expects msg.value to be bountyAmount + 10% platform fee
     * Example: If user wants 1 ETH bounty, they send 1.1 ETH total
     * - 1 ETH goes to the bounty
     * - 0.1 ETH goes to platform fee address
     */
    function createBounty(
        uint256 _systemId,
        string memory _systemName,
        address[] memory _existingNetworkNodeOwners
    ) external payable {
        require(msg.value > 0, "Must send ETH");
        require(bytes(_systemName).length > 0, "System name cannot be empty");

        // Calculate amounts: 
        // Total received = bounty amount + platform fee
        // Platform fee = 10% of bounty amount
        // So if bounty = X, total = X + 0.1X = 1.1X
        // Therefore: bounty = total / 1.1, fee = total - bounty
        
        uint256 totalReceived = msg.value;
        uint256 bountyAmount = (totalReceived * 100) / 110; // bounty = total / 1.1
        uint256 platformFee = totalReceived - bountyAmount;  // fee = total - bounty

        require(bountyAmount > 0, "Bounty amount must be greater than 0");

        // Transfer platform fee immediately
        (bool feeSuccess, ) = PLATFORM_FEE_ADDRESS.call{value: platformFee}("");
        require(feeSuccess, "Platform fee transfer failed");

        // Create the bounty with the calculated bounty amount
        bounties[bountyCounter] = Bounty({
            creator: msg.sender,
            systemId: _systemId,
            systemName: _systemName,
            amount: bountyAmount,
            createdAt: block.timestamp,
            claimed: false,
            claimedBy: address(0)
        });

        // Store excluded addresses (existing NetworkNode owners)
        for (uint256 i = 0; i < _existingNetworkNodeOwners.length; i++) {
            bountyExcludedAddresses[bountyCounter].push(_existingNetworkNodeOwners[i]);
        }

        // Add to system bounties mapping
        systemBounties[_systemId].push(bountyCounter);

        emit BountyCreated(
            bountyCounter,
            _systemId,
            _systemName,
            msg.sender,
            bountyAmount,
            _existingNetworkNodeOwners
        );

        emit PlatformFeeTransferred(bountyCounter, PLATFORM_FEE_ADDRESS, platformFee);

        bountyCounter++;
    }

    /**
     * @dev Claim a bounty by providing proof of NetworkNode ownership
     * @param _bountyId The ID of the bounty to claim
     */
    function claimBounty(uint256 _bountyId)
        external
        bountyExists(_bountyId)
        bountyNotClaimed(_bountyId)
    {
        require(canAddressClaimBounty(_bountyId, msg.sender), "Cannot claim this bounty");

        Bounty storage bounty = bounties[_bountyId];
        bounty.claimed = true;
        bounty.claimedBy = msg.sender;

        // Transfer the bounty amount to the claimer
        (bool success, ) = msg.sender.call{value: bounty.amount}("");
        require(success, "Bounty transfer failed");

        emit BountyClaimed(_bountyId, msg.sender, bounty.systemId);
    }

    /**
     * @dev Cancel a bounty and refund the creator (minus platform fee which was already sent)
     * @param _bountyId The ID of the bounty to cancel
     */
    function cancelBounty(uint256 _bountyId)
        external
        onlyBountyCreator(_bountyId)
        bountyExists(_bountyId)
        bountyNotClaimed(_bountyId)
    {
        Bounty storage bounty = bounties[_bountyId];
        uint256 refundAmount = bounty.amount;
        
        // Mark as claimed to prevent double-spending
        bounty.claimed = true;
        bounty.claimedBy = address(0);

        // Refund the bounty amount (platform fee was already taken)
        (bool success, ) = msg.sender.call{value: refundAmount}("");
        require(success, "Refund transfer failed");

        emit BountyCancelled(_bountyId);
    }

    /**
     * @dev Check if an address can claim a specific bounty
     * @param _bountyId The bounty ID to check
     * @param _address The address to check eligibility for
     * @return bool Whether the address can claim the bounty
     */
    function canAddressClaimBounty(uint256 _bountyId, address _address)
        public
        view
        bountyExists(_bountyId)
        returns (bool)
    {
        // Cannot claim your own bounty
        if (bounties[_bountyId].creator == _address) {
            return false;
        }

        // Check if address is in excluded list
        address[] memory excluded = bountyExcludedAddresses[_bountyId];
        for (uint256 i = 0; i < excluded.length; i++) {
            if (excluded[i] == _address) {
                return false;
            }
        }

        return true;
    }

    /**
     * @dev Get all bounty IDs for a specific system
     * @param _systemId The system ID to get bounties for
     * @return uint256[] Array of bounty IDs
     */
    function getBountiesOnSystem(uint256 _systemId) external view returns (uint256[] memory) {
        return systemBounties[_systemId];
    }

    /**
     * @dev Get active (unclaimed) bounty IDs for a specific system
     * @param _systemId The system ID to get active bounties for
     * @return uint256[] Array of active bounty IDs
     */
    function getActiveBountiesOnSystem(uint256 _systemId) external view returns (uint256[] memory) {
        uint256[] memory allBounties = systemBounties[_systemId];
        uint256 activeCount = 0;

        // First pass: count active bounties
        for (uint256 i = 0; i < allBounties.length; i++) {
            if (!bounties[allBounties[i]].claimed) {
                activeCount++;
            }
        }

        // Second pass: collect active bounties
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

    /**
     * @dev Get total bounty value for a specific system
     * @param _systemId The system ID to get total value for
     * @return uint256 Total value of active bounties in wei
     */
    function getTotalBountyOnSystem(uint256 _systemId) external view returns (uint256) {
        uint256[] memory allBounties = systemBounties[_systemId];
        uint256 totalValue = 0;

        for (uint256 i = 0; i < allBounties.length; i++) {
            if (!bounties[allBounties[i]].claimed) {
                totalValue += bounties[allBounties[i]].amount;
            }
        }

        return totalValue;
    }

    /**
     * @dev Get excluded addresses for a specific bounty
     * @param _bountyId The bounty ID to get excluded addresses for
     * @return address[] Array of excluded addresses
     */
    function getBountyExcludedAddresses(uint256 _bountyId)
        external
        view
        bountyExists(_bountyId)
        returns (address[] memory)
    {
        return bountyExcludedAddresses[_bountyId];
    }

    /**
     * @dev Get contract balance (should be 0 if working properly)
     * @return uint256 Contract balance in wei
     */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev Emergency function to recover any stuck ETH (admin only for emergencies)
     * Note: In a production environment, you might want to add access control here
     */
    function emergencyWithdraw() external {
        require(msg.sender == PLATFORM_FEE_ADDRESS, "Only platform can call emergency withdraw");
        require(address(this).balance > 0, "No balance to withdraw");
        
        (bool success, ) = PLATFORM_FEE_ADDRESS.call{value: address(this).balance}("");
        require(success, "Emergency withdrawal failed");
    }
}
