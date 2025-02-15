// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import { SignatureDrop, IDropSinglePhase, IDelayedReveal, ISignatureMintERC721, ERC721AUpgradeable, IPermissions, ILazyMint } from "contracts/signature-drop/SignatureDrop.sol";

// Test imports
import "erc721a-upgradeable/contracts/IERC721AUpgradeable.sol";
import "contracts/lib/TWStrings.sol";
import "./utils/BaseTest.sol";
import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract SignatureDropBenchmarkTest is BaseTest {
    using StringsUpgradeable for uint256;

    SignatureDrop public sigdrop;
    address internal deployerSigner;
    bytes32 internal typehashMintRequest;
    bytes32 internal nameHash;
    bytes32 internal versionHash;
    bytes32 internal typehashEip712;
    bytes32 internal domainSeparator;

    SignatureDrop.AllowlistProof alp;
    SignatureDrop.MintRequest _mintrequest;
    bytes _signature;

    using stdStorage for StdStorage;

    function setUp() public override {
        super.setUp();
        deployerSigner = signer;
        sigdrop = SignatureDrop(getContract("SignatureDrop"));

        erc20.mint(deployerSigner, 1_000_000);
        vm.deal(deployerSigner, 1_000);

        typehashMintRequest = keccak256(
            "MintRequest(address to,address royaltyRecipient,uint256 royaltyBps,address primarySaleRecipient,string uri,uint256 quantity,uint256 pricePerToken,address currency,uint128 validityStartTimestamp,uint128 validityEndTimestamp,bytes32 uid)"
        );
        nameHash = keccak256(bytes("SignatureMintERC721"));
        versionHash = keccak256(bytes("1"));
        typehashEip712 = keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
        domainSeparator = keccak256(abi.encode(typehashEip712, nameHash, versionHash, block.chainid, address(sigdrop)));

        // ==========================

        bytes32[] memory proofs = new bytes32[](0);
        alp.proof = proofs;

        SignatureDrop.ClaimCondition[] memory conditions = new SignatureDrop.ClaimCondition[](1);
        conditions[0].maxClaimableSupply = 100;
        conditions[0].quantityLimitPerTransaction = 100;
        conditions[0].waitTimeInSecondsBetweenClaims = type(uint256).max;

        vm.prank(deployerSigner);
        sigdrop.lazyMint(100, "ipfs://", "");
        vm.prank(deployerSigner);
        sigdrop.setClaimConditions(conditions[0], false);
        uint256 id = 0;

        _mintrequest.to = address(0);
        _mintrequest.royaltyRecipient = address(2);
        _mintrequest.royaltyBps = 0;
        _mintrequest.primarySaleRecipient = address(deployer);
        _mintrequest.uri = "ipfs://";
        _mintrequest.quantity = 1;
        _mintrequest.pricePerToken = 1;
        _mintrequest.currency = address(erc20);
        _mintrequest.validityStartTimestamp = 1000;
        _mintrequest.validityEndTimestamp = 2000;
        _mintrequest.uid = bytes32(id);

        _signature = signMintRequest(_mintrequest, privateKey);
        vm.startPrank(deployerSigner, deployerSigner);

        vm.warp(1000);
        erc20.approve(address(sigdrop), 1);
    }

    function signMintRequest(SignatureDrop.MintRequest memory _request, uint256 privateKey)
        internal
        returns (bytes memory)
    {
        bytes memory encodedRequest = abi.encode(
            typehashMintRequest,
            _request.to,
            _request.royaltyRecipient,
            _request.royaltyBps,
            _request.primarySaleRecipient,
            keccak256(bytes(_request.uri)),
            _request.quantity,
            _request.pricePerToken,
            _request.currency,
            _request.validityStartTimestamp,
            _request.validityEndTimestamp,
            _request.uid
        );
        bytes32 structHash = keccak256(encodedRequest);
        bytes32 typedDataHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, typedDataHash);
        bytes memory sig = abi.encodePacked(r, s, v);

        return sig;
    }

    function test_benchmark_mintWithSignature() public {
        sigdrop.mintWithSignature(_mintrequest, _signature);
    }

    function test_benchmark_claim() public {
        sigdrop.claim(address(25), 1, address(0), 0, alp, "");
    }
}

contract SignatureDropTest is BaseTest {
    using StringsUpgradeable for uint256;

    event TokensLazyMinted(uint256 indexed startTokenId, uint256 endTokenId, string baseURI, bytes encryptedBaseURI);
    event TokenURIRevealed(uint256 indexed index, string revealedURI);
    event TokensMintedWithSignature(
        address indexed signer,
        address indexed mintedTo,
        uint256 indexed tokenIdMinted,
        SignatureDrop.MintRequest mintRequest
    );

    SignatureDrop public sigdrop;
    address internal deployerSigner;
    bytes32 internal typehashMintRequest;
    bytes32 internal nameHash;
    bytes32 internal versionHash;
    bytes32 internal typehashEip712;
    bytes32 internal domainSeparator;

    using stdStorage for StdStorage;

    function setUp() public override {
        super.setUp();
        deployerSigner = signer;
        sigdrop = SignatureDrop(getContract("SignatureDrop"));

        erc20.mint(deployerSigner, 1_000_000);
        vm.deal(deployerSigner, 1_000);

        typehashMintRequest = keccak256(
            "MintRequest(address to,address royaltyRecipient,uint256 royaltyBps,address primarySaleRecipient,string uri,uint256 quantity,uint256 pricePerToken,address currency,uint128 validityStartTimestamp,uint128 validityEndTimestamp,bytes32 uid)"
        );
        nameHash = keccak256(bytes("SignatureMintERC721"));
        versionHash = keccak256(bytes("1"));
        typehashEip712 = keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
        domainSeparator = keccak256(abi.encode(typehashEip712, nameHash, versionHash, block.chainid, address(sigdrop)));
    }

    /*///////////////////////////////////////////////////////////////
                        Unit tests: misc.
    //////////////////////////////////////////////////////////////*/

    /**
     *  note: Tests whether contract reverts when a non-holder renounces a role.
     */
    function test_revert_nonHolder_renounceRole() public {
        address caller = address(0x123);
        bytes32 role = keccak256("MINTER_ROLE");

        vm.prank(caller);
        vm.expectRevert(
            abi.encodePacked(
                "Permissions: account ",
                TWStrings.toHexString(uint160(caller), 20),
                " is missing role ",
                TWStrings.toHexString(uint256(role), 32)
            )
        );

        sigdrop.renounceRole(role, caller);
    }

    /**
     *  note: Tests whether contract reverts when a role admin revokes a role for a non-holder.
     */
    function test_revert_revokeRoleForNonHolder() public {
        address target = address(0x123);
        bytes32 role = keccak256("MINTER_ROLE");

        vm.prank(deployerSigner);
        vm.expectRevert(
            abi.encodePacked(
                "Permissions: account ",
                TWStrings.toHexString(uint160(target), 20),
                " is missing role ",
                TWStrings.toHexString(uint256(role), 32)
            )
        );

        sigdrop.revokeRole(role, target);
    }

    /**
     *  @dev Tests whether contract reverts when a role is granted to an existent role holder.
     */
    function test_revert_grant_role_to_account_with_role() public {
        bytes32 role = keccak256("ABC_ROLE");
        address receiver = getActor(0);

        vm.startPrank(deployerSigner);

        sigdrop.grantRole(role, receiver);

        vm.expectRevert(abi.encodeWithSelector(IPermissions.Permissions__CanOnlyGrantToNonHolders.selector, receiver));
        sigdrop.grantRole(role, receiver);

        vm.stopPrank();
    }

    /**
     *  @dev Tests whether role member count is incremented correctly.
     */
    function test_member_count_incremented_properly_when_role_granted() public {
        bytes32 role = keccak256("ABC_ROLE");
        address receiver = getActor(0);

        vm.startPrank(deployerSigner);
        uint256 roleMemberCount = sigdrop.getRoleMemberCount(role);

        assertEq(roleMemberCount, 0);

        sigdrop.grantRole(role, receiver);

        assertEq(sigdrop.getRoleMemberCount(role), 1);

        vm.stopPrank();
    }

    function test_claimCondition_with_startTimestamp() public {
        vm.warp(1);

        address receiver = getActor(0);
        bytes32[] memory proofs = new bytes32[](0);

        SignatureDrop.AllowlistProof memory alp;
        alp.proof = proofs;

        SignatureDrop.ClaimCondition[] memory conditions = new SignatureDrop.ClaimCondition[](1);
        conditions[0].startTimestamp = 100;
        conditions[0].maxClaimableSupply = 100;
        conditions[0].quantityLimitPerTransaction = 100;
        conditions[0].waitTimeInSecondsBetweenClaims = type(uint256).max;

        vm.prank(deployerSigner);
        sigdrop.lazyMint(100, "ipfs://", "");

        vm.prank(deployerSigner);
        sigdrop.setClaimConditions(conditions[0], false);

        vm.warp(100);
        vm.prank(getActor(4), getActor(4));
        sigdrop.claim(receiver, 1, address(0), 0, alp, "");

        vm.warp(99);
        vm.prank(getActor(5), getActor(5));
        vm.expectRevert(
            abi.encodeWithSelector(
                IDropSinglePhase.DropSinglePhase__CannotClaimYet.selector,
                block.timestamp,
                conditions[0].startTimestamp,
                0,
                type(uint256).max
            )
        );
        sigdrop.claim(receiver, 1, address(0), 0, alp, "");
    }

    /*///////////////////////////////////////////////////////////////
                            Lazy Mint Tests
    //////////////////////////////////////////////////////////////*/

    /*
     *  note: Testing state changes; lazy mint a batch of tokens with no encrypted base URI.
     */
    function test_state_lazyMint_noEncryptedURI() public {
        uint256 amountToLazyMint = 100;
        string memory baseURI = "ipfs://";
        bytes memory encryptedBaseURI = "";

        uint256 nextTokenIdToMintBefore = sigdrop.nextTokenIdToMint();

        vm.startPrank(deployerSigner);
        uint256 batchId = sigdrop.lazyMint(amountToLazyMint, baseURI, encryptedBaseURI);

        assertEq(nextTokenIdToMintBefore + amountToLazyMint, sigdrop.nextTokenIdToMint());
        assertEq(nextTokenIdToMintBefore + amountToLazyMint, batchId);

        for (uint256 i = 0; i < amountToLazyMint; i += 1) {
            string memory uri = sigdrop.tokenURI(i);
            console.log(uri);
            assertEq(uri, string(abi.encodePacked(baseURI, i.toString())));
        }

        vm.stopPrank();
    }

    /*
     *  note: Testing state changes; lazy mint a batch of tokens with encrypted base URI.
     */
    function test_state_lazyMint_withEncryptedURI() public {
        uint256 amountToLazyMint = 100;
        string memory baseURI = "ipfs://";
        bytes memory encryptedBaseURI = "encryptedBaseURI://";

        uint256 nextTokenIdToMintBefore = sigdrop.nextTokenIdToMint();

        vm.startPrank(deployerSigner);
        uint256 batchId = sigdrop.lazyMint(amountToLazyMint, baseURI, encryptedBaseURI);

        assertEq(nextTokenIdToMintBefore + amountToLazyMint, sigdrop.nextTokenIdToMint());
        assertEq(nextTokenIdToMintBefore + amountToLazyMint, batchId);

        for (uint256 i = 0; i < amountToLazyMint; i += 1) {
            string memory uri = sigdrop.tokenURI(1);
            assertEq(uri, string(abi.encodePacked(baseURI, "0")));
        }

        vm.stopPrank();
    }

    /**
     *  note: Testing revert condition; an address without MINTER_ROLE calls lazyMint function.
     */
    function test_revert_lazyMint_MINTER_ROLE() public {
        bytes memory errorMessage = abi.encodePacked(
            "Permissions: account ",
            Strings.toHexString(uint160(address(this)), 20),
            " is missing role ",
            Strings.toHexString(uint256(keccak256("MINTER_ROLE")), 32)
        );

        vm.expectRevert(errorMessage);
        sigdrop.lazyMint(100, "ipfs://", "");
    }

    /*
     *  note: Testing revert condition; calling tokenURI for invalid batch id.
     */
    function test_revert_lazyMint_URIForNonLazyMintedToken() public {
        vm.startPrank(deployerSigner);

        sigdrop.lazyMint(100, "ipfs://", "");

        vm.expectRevert(abi.encodeWithSelector(ILazyMint.LazyMint__NoBatchIDForToken.selector, 100));
        sigdrop.tokenURI(100);

        vm.stopPrank();
    }

    /**
     *  note: Testing event emission; tokens lazy minted.
     */
    function test_event_lazyMint_TokensLazyMinted() public {
        vm.startPrank(deployerSigner);

        vm.expectEmit(true, false, false, true);
        emit TokensLazyMinted(0, 99, "ipfs://", "");
        sigdrop.lazyMint(100, "ipfs://", "");

        vm.stopPrank();
    }

    /*
     *  note: Fuzz testing state changes; lazy mint a batch of tokens with no encrypted base URI.
     */
    function test_fuzz_lazyMint_noEncryptedURI(uint256 x) public {
        vm.assume(x > 0);

        uint256 amountToLazyMint = x;
        string memory baseURI = "ipfs://";
        bytes memory encryptedBaseURI = "";

        uint256 nextTokenIdToMintBefore = sigdrop.nextTokenIdToMint();

        vm.startPrank(deployerSigner);
        uint256 batchId = sigdrop.lazyMint(amountToLazyMint, baseURI, encryptedBaseURI);

        assertEq(nextTokenIdToMintBefore + amountToLazyMint, sigdrop.nextTokenIdToMint());
        assertEq(nextTokenIdToMintBefore + amountToLazyMint, batchId);

        string memory uri = sigdrop.tokenURI(0);
        assertEq(uri, string(abi.encodePacked(baseURI, uint256(0).toString())));

        uri = sigdrop.tokenURI(x - 1);
        assertEq(uri, string(abi.encodePacked(baseURI, uint256(x - 1).toString())));

        /**
         *  note: this loop takes too long to run with fuzz tests.
         */
        // for(uint256 i = 0; i < amountToLazyMint; i += 1) {
        //     string memory uri = sigdrop.tokenURI(i);
        //     console.log(uri);
        //     assertEq(uri, string(abi.encodePacked(baseURI, i.toString())));
        // }

        vm.stopPrank();
    }

    /*
     *  note: Fuzz testing state changes; lazy mint a batch of tokens with encrypted base URI.
     */
    function test_fuzz_lazyMint_withEncryptedURI(uint256 x) public {
        vm.assume(x > 0);

        uint256 amountToLazyMint = x;
        string memory baseURI = "ipfs://";
        bytes memory encryptedBaseURI = "encryptedBaseURI://";

        uint256 nextTokenIdToMintBefore = sigdrop.nextTokenIdToMint();

        vm.startPrank(deployerSigner);
        uint256 batchId = sigdrop.lazyMint(amountToLazyMint, baseURI, encryptedBaseURI);

        assertEq(nextTokenIdToMintBefore + amountToLazyMint, sigdrop.nextTokenIdToMint());
        assertEq(nextTokenIdToMintBefore + amountToLazyMint, batchId);

        string memory uri = sigdrop.tokenURI(0);
        assertEq(uri, string(abi.encodePacked(baseURI, "0")));

        uri = sigdrop.tokenURI(x - 1);
        assertEq(uri, string(abi.encodePacked(baseURI, "0")));

        /**
         *  note: this loop takes too long to run with fuzz tests.
         */
        // for(uint256 i = 0; i < amountToLazyMint; i += 1) {
        //     string memory uri = sigdrop.tokenURI(1);
        //     assertEq(uri, string(abi.encodePacked(baseURI, "0")));
        // }

        vm.stopPrank();
    }

    /*
     *  note: Fuzz testing; a batch of tokens, and nextTokenIdToMint
     */
    function test_fuzz_lazyMint_batchMintAndNextTokenIdToMint(uint256 x) public {
        vm.assume(x > 0);
        vm.startPrank(deployerSigner);

        if (x == 0) {
            vm.expectRevert("Zero amount");
        }
        sigdrop.lazyMint(x, "ipfs://", "");

        uint256 slot = stdstore.target(address(sigdrop)).sig("nextTokenIdToMint()").find();
        bytes32 loc = bytes32(slot);
        uint256 nextTokenIdToMint = uint256(vm.load(address(sigdrop), loc));

        assertEq(nextTokenIdToMint, x);
        vm.stopPrank();
    }

    /*///////////////////////////////////////////////////////////////
                        Delayed Reveal Tests
    //////////////////////////////////////////////////////////////*/

    /*
     *  note: Testing state changes; URI revealed for a batch of tokens.
     */
    function test_state_reveal() public {
        vm.startPrank(deployerSigner);

        bytes memory key = "key";
        uint256 amountToLazyMint = 100;
        bytes memory secretURI = "ipfs://";
        string memory placeholderURI = "ipfs://";
        bytes memory encryptedURI = sigdrop.encryptDecrypt(secretURI, key);
        sigdrop.lazyMint(amountToLazyMint, placeholderURI, encryptedURI);

        for (uint256 i = 0; i < amountToLazyMint; i += 1) {
            string memory uri = sigdrop.tokenURI(i);
            assertEq(uri, string(abi.encodePacked(placeholderURI, "0")));
        }

        string memory revealedURI = sigdrop.reveal(0, key);
        assertEq(revealedURI, string(secretURI));

        for (uint256 i = 0; i < amountToLazyMint; i += 1) {
            string memory uri = sigdrop.tokenURI(i);
            assertEq(uri, string(abi.encodePacked(secretURI, i.toString())));
        }

        vm.stopPrank();
    }

    /**
     *  note: Testing revert condition; an address without MINTER_ROLE calls reveal function.
     */
    function test_revert_reveal_MINTER_ROLE() public {
        bytes memory encryptedURI = sigdrop.encryptDecrypt("ipfs://", "key");
        vm.prank(deployerSigner);
        sigdrop.lazyMint(100, "", encryptedURI);

        vm.prank(deployerSigner);
        sigdrop.reveal(0, "key");

        bytes memory errorMessage = abi.encodePacked(
            "Permissions: account ",
            Strings.toHexString(uint160(address(this)), 20),
            " is missing role ",
            Strings.toHexString(uint256(keccak256("MINTER_ROLE")), 32)
        );

        vm.expectRevert(errorMessage);
        sigdrop.reveal(0, "key");
    }

    /*
     *  note: Testing revert condition; trying to reveal URI for non-existent batch.
     */
    function test_revert_reveal_revealingNonExistentBatch() public {
        vm.startPrank(deployerSigner);

        bytes memory encryptedURI = sigdrop.encryptDecrypt("ipfs://", "key");
        sigdrop.lazyMint(100, "", encryptedURI);
        sigdrop.reveal(0, "key");

        console.log(sigdrop.getBaseURICount());

        sigdrop.lazyMint(100, "", encryptedURI);
        vm.expectRevert(abi.encodeWithSelector(ILazyMint.LazyMint__InvalidIndex.selector, 2));
        sigdrop.reveal(2, "key");

        vm.stopPrank();
    }

    /*
     *  note: Testing revert condition; already revealed URI.
     */
    function test_revert_delayedReveal_alreadyRevealed() public {
        vm.startPrank(deployerSigner);

        bytes memory encryptedURI = sigdrop.encryptDecrypt("ipfs://", "key");
        sigdrop.lazyMint(100, "", encryptedURI);
        sigdrop.reveal(0, "key");

        vm.expectRevert(abi.encodeWithSelector(IDelayedReveal.DelayedReveal__NothingToReveal.selector, 100));
        sigdrop.reveal(0, "key");

        vm.stopPrank();
    }

    /*
     *  note: Testing state changes; revealing URI with an incorrect key.
     */
    function testFail_reveal_incorrectKey() public {
        vm.startPrank(deployerSigner);

        bytes memory encryptedURI = sigdrop.encryptDecrypt("ipfs://", "key");
        sigdrop.lazyMint(100, "", encryptedURI);

        string memory revealedURI = sigdrop.reveal(0, "keyy");
        assertEq(revealedURI, "ipfs://");

        vm.stopPrank();
    }

    /**
     *  note: Testing event emission; TokenURIRevealed.
     */
    function test_event_reveal_TokenURIRevealed() public {
        vm.startPrank(deployerSigner);

        bytes memory encryptedURI = sigdrop.encryptDecrypt("ipfs://", "key");
        sigdrop.lazyMint(100, "", encryptedURI);

        vm.expectEmit(true, false, false, true);
        emit TokenURIRevealed(0, "ipfs://");
        sigdrop.reveal(0, "key");

        vm.stopPrank();
    }

    /*///////////////////////////////////////////////////////////////
                        Signature Mint Tests
    //////////////////////////////////////////////////////////////*/

    function signMintRequest(SignatureDrop.MintRequest memory mintrequest, uint256 privateKey)
        internal
        returns (bytes memory)
    {
        bytes memory encodedRequest = abi.encode(
            typehashMintRequest,
            mintrequest.to,
            mintrequest.royaltyRecipient,
            mintrequest.royaltyBps,
            mintrequest.primarySaleRecipient,
            keccak256(bytes(mintrequest.uri)),
            mintrequest.quantity,
            mintrequest.pricePerToken,
            mintrequest.currency,
            mintrequest.validityStartTimestamp,
            mintrequest.validityEndTimestamp,
            mintrequest.uid
        );
        bytes32 structHash = keccak256(encodedRequest);
        bytes32 typedDataHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, typedDataHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        return signature;
    }

    /*
     *  note: Testing state changes; minting with signature, for a given price and currency.
     */
    function test_state_mintWithSignature() public {
        vm.prank(deployerSigner);
        sigdrop.lazyMint(100, "ipfs://", "");
        uint256 id = 0;
        SignatureDrop.MintRequest memory mintrequest;

        mintrequest.to = address(0);
        mintrequest.royaltyRecipient = address(2);
        mintrequest.royaltyBps = 0;
        mintrequest.primarySaleRecipient = address(deployer);
        mintrequest.uri = "ipfs://";
        mintrequest.quantity = 1;
        mintrequest.pricePerToken = 1;
        mintrequest.currency = address(erc20);
        mintrequest.validityStartTimestamp = 1000;
        mintrequest.validityEndTimestamp = 2000;
        mintrequest.uid = bytes32(id);

        // Test with ERC20 currency
        {
            uint256 totalSupplyBefore = sigdrop.totalSupply();

            bytes memory signature = signMintRequest(mintrequest, privateKey);
            vm.startPrank(deployerSigner);
            vm.warp(1000);
            erc20.approve(address(sigdrop), 1);
            vm.expectEmit(true, true, true, false);
            emit TokensMintedWithSignature(deployerSigner, deployerSigner, 0, mintrequest);
            sigdrop.mintWithSignature(mintrequest, signature);
            vm.stopPrank();

            assertEq(totalSupplyBefore + mintrequest.quantity, sigdrop.totalSupply());
        }

        // Test with native token currency
        {
            uint256 totalSupplyBefore = sigdrop.totalSupply();

            mintrequest.currency = address(NATIVE_TOKEN);
            id = 1;
            mintrequest.uid = bytes32(id);

            bytes memory signature = signMintRequest(mintrequest, privateKey);
            vm.startPrank(address(deployerSigner));
            vm.warp(1000);
            sigdrop.mintWithSignature{ value: mintrequest.pricePerToken }(mintrequest, signature);
            vm.stopPrank();

            assertEq(totalSupplyBefore + mintrequest.quantity, sigdrop.totalSupply());
        }
    }

    /**
     *  note: Testing revert condition; invalid signature.
     */
    function test_revert_mintWithSignature_unapprovedSigner() public {
        vm.prank(deployerSigner);
        sigdrop.lazyMint(100, "ipfs://", "");
        uint256 id = 0;

        SignatureDrop.MintRequest memory mintrequest;
        mintrequest.to = address(0);
        mintrequest.royaltyRecipient = address(2);
        mintrequest.royaltyBps = 0;
        mintrequest.primarySaleRecipient = address(deployer);
        mintrequest.uri = "ipfs://";
        mintrequest.quantity = 1;
        mintrequest.pricePerToken = 0;
        mintrequest.currency = address(3);
        mintrequest.validityStartTimestamp = 1000;
        mintrequest.validityEndTimestamp = 2000;
        mintrequest.uid = bytes32(id);

        bytes memory signature = signMintRequest(mintrequest, privateKey);
        vm.warp(1000);
        vm.prank(deployerSigner);
        sigdrop.mintWithSignature(mintrequest, signature);

        signature = signMintRequest(mintrequest, 4321);
        vm.expectRevert(abi.encodeWithSelector(ISignatureMintERC721.SignatureMintERC721__InvalidRequest.selector));
        sigdrop.mintWithSignature(mintrequest, signature);
    }

    /**
     *  note: Testing revert condition; not enough minted tokens.
     */
    function test_revert_mintWithSignature_notEnoughMintedTokens() public {
        vm.prank(deployerSigner);
        sigdrop.lazyMint(100, "ipfs://", "");
        uint256 id = 0;

        SignatureDrop.MintRequest memory mintrequest;
        mintrequest.to = address(0);
        mintrequest.royaltyRecipient = address(2);
        mintrequest.royaltyBps = 0;
        mintrequest.primarySaleRecipient = address(deployer);
        mintrequest.uri = "ipfs://";
        mintrequest.quantity = 101;
        mintrequest.pricePerToken = 0;
        mintrequest.currency = address(3);
        mintrequest.validityStartTimestamp = 1000;
        mintrequest.validityEndTimestamp = 2000;
        mintrequest.uid = bytes32(id);

        bytes memory signature = signMintRequest(mintrequest, privateKey);
        vm.warp(1000);
        vm.expectRevert(
            abi.encodeWithSelector(SignatureDrop.SignatureDrop__NotEnoughMintedTokens.selector, 0, mintrequest.quantity)
        );
        sigdrop.mintWithSignature(mintrequest, signature);
    }

    /**
     *  note: Testing revert condition; sent value is not equal to price.
     */
    function test_revert_mintWithSignature_notSentAmountRequired() public {
        vm.prank(deployerSigner);
        sigdrop.lazyMint(100, "ipfs://", "");
        uint256 id = 0;
        SignatureDrop.MintRequest memory mintrequest;

        mintrequest.to = address(0);
        mintrequest.royaltyRecipient = address(2);
        mintrequest.royaltyBps = 0;
        mintrequest.primarySaleRecipient = address(deployer);
        mintrequest.uri = "ipfs://";
        mintrequest.quantity = 1;
        mintrequest.pricePerToken = 1;
        mintrequest.currency = address(3);
        mintrequest.validityStartTimestamp = 1000;
        mintrequest.validityEndTimestamp = 2000;
        mintrequest.uid = bytes32(id);
        {
            mintrequest.currency = address(NATIVE_TOKEN);
            bytes memory signature = signMintRequest(mintrequest, privateKey);
            vm.startPrank(address(deployerSigner));
            vm.warp(mintrequest.validityStartTimestamp);
            vm.expectRevert(abi.encodeWithSelector(SignatureDrop.SignatureDrop__MustSendTotalPrice.selector, 2, 1));
            sigdrop.mintWithSignature{ value: 2 }(mintrequest, signature);
            vm.stopPrank();
        }
    }

    /**
     *  note: Testing token balances; checking balance and owner of tokens after minting with signature.
     */
    function test_balances_mintWithSignature() public {
        vm.prank(deployerSigner);
        sigdrop.lazyMint(100, "ipfs://", "");
        uint256 id = 0;
        SignatureDrop.MintRequest memory mintrequest;

        mintrequest.to = address(0);
        mintrequest.royaltyRecipient = address(2);
        mintrequest.royaltyBps = 0;
        mintrequest.primarySaleRecipient = address(deployer);
        mintrequest.uri = "ipfs://";
        mintrequest.quantity = 1;
        mintrequest.pricePerToken = 1;
        mintrequest.currency = address(erc20);
        mintrequest.validityStartTimestamp = 1000;
        mintrequest.validityEndTimestamp = 2000;
        mintrequest.uid = bytes32(id);

        {
            uint256 currencyBalBefore = erc20.balanceOf(deployerSigner);

            bytes memory signature = signMintRequest(mintrequest, privateKey);
            vm.startPrank(deployerSigner);
            vm.warp(1000);
            erc20.approve(address(sigdrop), 1);
            sigdrop.mintWithSignature(mintrequest, signature);
            vm.stopPrank();

            uint256 balance = sigdrop.balanceOf(address(deployerSigner));
            assertEq(balance, 1);

            address owner = sigdrop.ownerOf(0);
            assertEq(deployerSigner, owner);

            assertEq(
                currencyBalBefore - mintrequest.pricePerToken * mintrequest.quantity,
                erc20.balanceOf(deployerSigner)
            );

            vm.expectRevert(abi.encodeWithSelector(IERC721AUpgradeable.OwnerQueryForNonexistentToken.selector));
            owner = sigdrop.ownerOf(1);
        }
    }

    /*
     *  note: Testing state changes; minting with signature, for a given price and currency.
     */
    function mintWithSignature(SignatureDrop.MintRequest memory mintrequest) internal {
        vm.prank(deployerSigner);
        sigdrop.lazyMint(100, "ipfs://", "");
        uint256 id = 0;

        {
            bytes memory signature = signMintRequest(mintrequest, privateKey);
            vm.startPrank(deployerSigner);
            vm.warp(mintrequest.validityStartTimestamp);
            erc20.approve(address(sigdrop), 1);
            sigdrop.mintWithSignature(mintrequest, signature);
            vm.stopPrank();
        }

        {
            mintrequest.currency = address(NATIVE_TOKEN);
            id = 1;
            mintrequest.uid = bytes32(id);
            bytes memory signature = signMintRequest(mintrequest, privateKey);
            vm.startPrank(address(deployerSigner));
            vm.warp(mintrequest.validityStartTimestamp);
            sigdrop.mintWithSignature{ value: mintrequest.pricePerToken }(mintrequest, signature);
            vm.stopPrank();
        }
    }

    function test_fuzz_mintWithSignature(uint128 x, uint128 y) public {
        if (x < y) {
            uint256 id = 0;
            SignatureDrop.MintRequest memory mintrequest;

            mintrequest.to = address(0);
            mintrequest.royaltyRecipient = address(2);
            mintrequest.royaltyBps = 0;
            mintrequest.primarySaleRecipient = address(deployer);
            mintrequest.uri = "ipfs://";
            mintrequest.quantity = 1;
            mintrequest.pricePerToken = 1;
            mintrequest.currency = address(erc20);
            mintrequest.validityStartTimestamp = x;
            mintrequest.validityEndTimestamp = y;
            mintrequest.uid = bytes32(id);

            mintWithSignature(mintrequest);
        }
    }

    /*///////////////////////////////////////////////////////////////
                                Claim Tests
    //////////////////////////////////////////////////////////////*/

    /**
     *  note: Testing revert condition; not allowed to claim again before wait time is over.
     */
    function test_revert_claimCondition_waitTimeInSecondsBetweenClaims() public {
        vm.warp(1);

        address receiver = getActor(0);
        bytes32[] memory proofs = new bytes32[](0);

        SignatureDrop.AllowlistProof memory alp;
        alp.proof = proofs;

        SignatureDrop.ClaimCondition[] memory conditions = new SignatureDrop.ClaimCondition[](1);
        conditions[0].maxClaimableSupply = 100;
        conditions[0].quantityLimitPerTransaction = 100;
        conditions[0].waitTimeInSecondsBetweenClaims = type(uint256).max;

        vm.prank(deployerSigner);
        sigdrop.lazyMint(100, "ipfs://", "");
        vm.prank(deployerSigner);
        sigdrop.setClaimConditions(conditions[0], false);

        vm.prank(getActor(5), getActor(5));
        sigdrop.claim(receiver, 1, address(0), 0, alp, "");

        vm.expectRevert(
            abi.encodeWithSelector(
                IDropSinglePhase.DropSinglePhase__CannotClaimYet.selector,
                block.timestamp,
                0,
                1,
                type(uint256).max
            )
        );
        vm.prank(getActor(5), getActor(5));
        sigdrop.claim(receiver, 1, address(0), 0, alp, "");
    }

    /**
     *  note: Testing revert condition; not enough minted tokens.
     */
    function test_revert_claimCondition_notEnoughMintedTokens() public {
        vm.warp(1);

        address receiver = getActor(0);
        bytes32[] memory proofs = new bytes32[](0);

        SignatureDrop.AllowlistProof memory alp;
        alp.proof = proofs;

        SignatureDrop.ClaimCondition[] memory conditions = new SignatureDrop.ClaimCondition[](1);
        conditions[0].maxClaimableSupply = 100;
        conditions[0].quantityLimitPerTransaction = 100;
        conditions[0].waitTimeInSecondsBetweenClaims = type(uint256).max;

        vm.prank(deployerSigner);
        sigdrop.lazyMint(100, "ipfs://", "");
        vm.prank(deployerSigner);
        sigdrop.setClaimConditions(conditions[0], false);

        vm.expectRevert(abi.encodeWithSelector(SignatureDrop.SignatureDrop__NotEnoughMintedTokens.selector, 0, 101));
        vm.prank(getActor(6), getActor(6));
        sigdrop.claim(receiver, 101, address(0), 0, alp, "");
    }

    /**
     *  note: Testing revert condition; exceed max claimable supply.
     */
    function test_revert_claimCondition_exceedMaxClaimableSupply() public {
        vm.warp(1);

        address receiver = getActor(0);
        bytes32[] memory proofs = new bytes32[](0);

        SignatureDrop.AllowlistProof memory alp;
        alp.proof = proofs;

        SignatureDrop.ClaimCondition[] memory conditions = new SignatureDrop.ClaimCondition[](1);
        conditions[0].maxClaimableSupply = 100;
        conditions[0].quantityLimitPerTransaction = 100;
        conditions[0].waitTimeInSecondsBetweenClaims = type(uint256).max;

        vm.prank(deployerSigner);
        sigdrop.lazyMint(200, "ipfs://", "");
        vm.prank(deployerSigner);
        sigdrop.setClaimConditions(conditions[0], false);

        vm.prank(getActor(5), getActor(5));
        sigdrop.claim(receiver, 100, address(0), 0, alp, "");

        vm.expectRevert(
            abi.encodeWithSelector(IDropSinglePhase.DropSinglePhase__ExceedMaxClaimableSupply.selector, 100, 100)
        );
        vm.prank(getActor(6), getActor(6));
        sigdrop.claim(receiver, 1, address(0), 0, alp, "");
    }

    /**
     *  note: Testing quantity limit restriction when no allowlist present.
     */
    function test_fuzz_claim_noAllowlist(uint256 x) public {
        vm.assume(x != 0);
        vm.warp(1);

        address receiver = getActor(0);
        bytes32[] memory proofs = new bytes32[](0);

        SignatureDrop.AllowlistProof memory alp;
        alp.proof = proofs;
        alp.maxQuantityInAllowlist = x;

        SignatureDrop.ClaimCondition[] memory conditions = new SignatureDrop.ClaimCondition[](1);
        conditions[0].maxClaimableSupply = 500;
        conditions[0].quantityLimitPerTransaction = 100;
        conditions[0].waitTimeInSecondsBetweenClaims = type(uint256).max;

        vm.prank(deployerSigner);
        sigdrop.lazyMint(500, "ipfs://", bytes(""));

        vm.prank(deployerSigner);
        sigdrop.setClaimConditions(conditions[0], false);

        vm.prank(getActor(5), getActor(5));
        vm.expectRevert(abi.encodeWithSelector(IDropSinglePhase.DropSinglePhase__InvalidQuantity.selector));
        sigdrop.claim(receiver, 101, address(0), 0, alp, "");

        vm.prank(deployerSigner);
        sigdrop.setClaimConditions(conditions[0], true);

        vm.prank(getActor(5), getActor(5));
        vm.expectRevert(abi.encodeWithSelector(IDropSinglePhase.DropSinglePhase__InvalidQuantity.selector));
        sigdrop.claim(receiver, 101, address(0), 0, alp, "");
    }

    /**
     *  note: Testing revert condition; can't claim if not in whitelist.
     */
    function test_revert_claimCondition_merkleProof() public {
        string[] memory inputs = new string[](3);

        inputs[0] = "node";
        inputs[1] = "src/test/scripts/generateRoot.ts";
        inputs[2] = "1";

        bytes memory result = vm.ffi(inputs);
        bytes32 root = abi.decode(result, (bytes32));

        inputs[1] = "src/test/scripts/getProof.ts";
        result = vm.ffi(inputs);
        bytes32[] memory proofs = abi.decode(result, (bytes32[]));

        vm.warp(1);

        address receiver = address(0x92Bb439374a091c7507bE100183d8D1Ed2c9dAD3);

        SignatureDrop.AllowlistProof memory alp;
        alp.proof = proofs;
        alp.maxQuantityInAllowlist = 1;

        SignatureDrop.ClaimCondition[] memory conditions = new SignatureDrop.ClaimCondition[](1);
        conditions[0].maxClaimableSupply = 100;
        conditions[0].quantityLimitPerTransaction = 100;
        conditions[0].waitTimeInSecondsBetweenClaims = type(uint256).max;
        conditions[0].merkleRoot = root;

        vm.prank(deployerSigner);
        sigdrop.lazyMint(200, "ipfs://", "");
        vm.prank(deployerSigner);
        sigdrop.setClaimConditions(conditions[0], false);

        // vm.prank(getActor(5), getActor(5));
        vm.prank(receiver, receiver);
        sigdrop.claim(receiver, 1, address(0), 0, alp, "");

        vm.prank(address(4), address(4));
        vm.expectRevert(abi.encodeWithSelector(IDropSinglePhase.DropSinglePhase__NotInWhitelist.selector));
        sigdrop.claim(receiver, 1, address(0), 0, alp, "");
    }

    /**
     *  note: Testing state changes; reset eligibility of claim conditions and claiming again for same condition id.
     */
    function test_state_claimCondition_resetEligibility_waitTimeInSecondsBetweenClaims() public {
        vm.warp(1);

        address receiver = getActor(0);
        bytes32[] memory proofs = new bytes32[](0);

        SignatureDrop.AllowlistProof memory alp;
        alp.proof = proofs;

        SignatureDrop.ClaimCondition[] memory conditions = new SignatureDrop.ClaimCondition[](1);
        conditions[0].maxClaimableSupply = 100;
        conditions[0].quantityLimitPerTransaction = 100;
        conditions[0].waitTimeInSecondsBetweenClaims = type(uint256).max;

        vm.prank(deployerSigner);
        sigdrop.lazyMint(100, "ipfs://", "");

        vm.prank(deployerSigner);
        sigdrop.setClaimConditions(conditions[0], false);

        vm.prank(getActor(5), getActor(5));
        sigdrop.claim(receiver, 1, address(0), 0, alp, "");

        vm.prank(deployerSigner);
        sigdrop.setClaimConditions(conditions[0], true);

        vm.prank(getActor(5), getActor(5));
        sigdrop.claim(receiver, 1, address(0), 0, alp, "");
    }

    /*///////////////////////////////////////////////////////////////
                            Miscellaneous
    //////////////////////////////////////////////////////////////*/
    function test_breaking_reveal() public {
        address attacker = getActor(0);
        bytes memory encryptedURI = sigdrop.encryptDecrypt("ipfs://", "key");

        vm.prank(deployerSigner);
        sigdrop.lazyMint(100, "", encryptedURI);

        uint256 batchId = sigdrop.getBatchIdAtIndex(0);
        vm.prank(attacker);
        sigdrop.getRevealURI(batchId, "wrong keyy");

        vm.prank(deployerSigner);
        sigdrop.reveal(0, "key");
    }

    function test_delayedReveal_withNewLazyMintedEmptyBatch() public {
        vm.startPrank(deployerSigner);

        bytes memory encryptedURI = sigdrop.encryptDecrypt("ipfs://", "key");
        sigdrop.lazyMint(100, "", encryptedURI);
        sigdrop.reveal(0, "key");

        string memory uri = sigdrop.tokenURI(1);
        assertEq(uri, string(abi.encodePacked("ipfs://", "1")));

        bytes memory newEncryptedURI = sigdrop.encryptDecrypt("ipfs://secret", "key");
        vm.expectRevert(abi.encodeWithSelector(SignatureDrop.SignatureDrop__ZeroAmount.selector));
        sigdrop.lazyMint(0, "", newEncryptedURI);

        vm.stopPrank();
    }

    /*///////////////////////////////////////////////////////////////
                            Reentrancy related Tests
    //////////////////////////////////////////////////////////////*/

    function testFail_reentrancy_mintWithSignature() public {
        vm.prank(deployerSigner);
        sigdrop.lazyMint(100, "ipfs://", "");
        uint256 id = 0;
        SignatureDrop.MintRequest memory mintrequest;

        mintrequest.to = address(0);
        mintrequest.royaltyRecipient = address(2);
        mintrequest.royaltyBps = 0;
        mintrequest.primarySaleRecipient = address(deployer);
        mintrequest.uri = "ipfs://";
        mintrequest.quantity = 1;
        mintrequest.pricePerToken = 1;
        mintrequest.currency = address(NATIVE_TOKEN);
        mintrequest.validityStartTimestamp = 1000;
        mintrequest.validityEndTimestamp = 2000;
        mintrequest.uid = bytes32(id);

        // Test with native token currency
        {
            uint256 totalSupplyBefore = sigdrop.totalSupply();

            mintrequest.uid = bytes32(id);
            bytes memory signature = signMintRequest(mintrequest, privateKey);

            MaliciousReceiver mal = new MaliciousReceiver(address(sigdrop));
            vm.deal(address(mal), 100 ether);
            vm.warp(1000);
            mal.attackMintWithSignature(mintrequest, signature, false);

            assertEq(totalSupplyBefore + mintrequest.quantity, sigdrop.totalSupply());
        }
    }

    function testFail_reentrancy_claim() public {
        vm.warp(1);
        bytes32[] memory proofs = new bytes32[](0);

        SignatureDrop.AllowlistProof memory alp;
        alp.proof = proofs;

        SignatureDrop.ClaimCondition[] memory conditions = new SignatureDrop.ClaimCondition[](1);
        conditions[0].maxClaimableSupply = 100;
        conditions[0].quantityLimitPerTransaction = 100;
        conditions[0].waitTimeInSecondsBetweenClaims = type(uint256).max;

        vm.prank(deployerSigner);
        sigdrop.lazyMint(100, "ipfs://", "");

        vm.prank(deployerSigner);
        sigdrop.setClaimConditions(conditions[0], false);

        MaliciousReceiver mal = new MaliciousReceiver(address(sigdrop));
        vm.deal(address(mal), 100 ether);
        mal.attackClaim(alp, false);
    }

    function testFail_combination_signatureAndClaim() public {
        vm.warp(1);
        bytes32[] memory proofs = new bytes32[](0);

        SignatureDrop.AllowlistProof memory alp;
        alp.proof = proofs;

        SignatureDrop.ClaimCondition[] memory conditions = new SignatureDrop.ClaimCondition[](1);
        conditions[0].maxClaimableSupply = 100;
        conditions[0].quantityLimitPerTransaction = 100;
        conditions[0].waitTimeInSecondsBetweenClaims = type(uint256).max;

        vm.prank(deployerSigner);
        sigdrop.lazyMint(100, "ipfs://", "");
        vm.prank(deployerSigner);
        sigdrop.setClaimConditions(conditions[0], false);

        uint256 id = 0;
        SignatureDrop.MintRequest memory mintrequest;

        mintrequest.to = address(0);
        mintrequest.royaltyRecipient = address(2);
        mintrequest.royaltyBps = 0;
        mintrequest.primarySaleRecipient = address(deployer);
        mintrequest.uri = "ipfs://";
        mintrequest.quantity = 1;
        mintrequest.pricePerToken = 1;
        mintrequest.currency = address(NATIVE_TOKEN);
        mintrequest.validityStartTimestamp = 1000;
        mintrequest.validityEndTimestamp = 2000;
        mintrequest.uid = bytes32(id);

        // Test with native token currency
        {
            uint256 totalSupplyBefore = sigdrop.totalSupply();

            mintrequest.uid = bytes32(id);
            bytes memory signature = signMintRequest(mintrequest, privateKey);

            MaliciousReceiver mal = new MaliciousReceiver(address(sigdrop));
            vm.deal(address(mal), 100 ether);
            vm.warp(1000);
            mal.saveCombination(mintrequest, signature, alp);
            mal.attackMintWithSignature(mintrequest, signature, true);
            // mal.attackClaim(alp, true);

            assertEq(totalSupplyBefore + mintrequest.quantity, sigdrop.totalSupply());
        }
    }
}

contract MaliciousReceiver {
    SignatureDrop public sigdrop;

    SignatureDrop.MintRequest public mintrequest;
    SignatureDrop.AllowlistProof public alp;
    bytes public signature;
    bool public claim;
    bool public loop = true;

    constructor(address _sigdrop) {
        sigdrop = SignatureDrop(_sigdrop);
    }

    function attackMintWithSignature(
        SignatureDrop.MintRequest calldata _mintrequest,
        bytes calldata _signature,
        bool swap
    ) external {
        claim = swap;
        mintrequest = _mintrequest;
        signature = _signature;
        sigdrop.mintWithSignature{ value: _mintrequest.pricePerToken }(_mintrequest, _signature);
    }

    function attackClaim(SignatureDrop.AllowlistProof calldata _alp, bool swap) external {
        claim = !swap;
        alp = _alp;
        sigdrop.claim(address(this), 1, address(0), 0, _alp, "");
    }

    function saveCombination(
        SignatureDrop.MintRequest calldata _mintrequest,
        bytes calldata _signature,
        SignatureDrop.AllowlistProof calldata _alp
    ) external {
        mintrequest = _mintrequest;
        signature = _signature;
        alp = _alp;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external returns (bytes4) {
        if (claim && loop) {
            loop = false;
            claim = false;
            sigdrop.claim(address(this), 1, address(0), 0, alp, "");
        } else if (!claim && loop) {
            loop = false;
            sigdrop.mintWithSignature{ value: mintrequest.pricePerToken }(mintrequest, signature);
        }
        return this.onERC721Received.selector;
    }
}
