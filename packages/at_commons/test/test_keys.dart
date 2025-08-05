class TestKeys {
  List<String> validPublicKeys = [];
  List<String> invalidPublicKeysNamespaceMandatory = [];
  List<String> invalidPublicKeysNamespaceOptional = [];

  List<String> validPrivateKeys = [];
  List<String> invalidPrivateKeysNamespaceMandatory = [];
  List<String> invalidPrivateKeysNamespaceOptional = [];

  List<String> validSharedKeys = [];
  List<String> invalidSharedKeysNamespaceMandatory = [];
  List<String> invalidSharedKeysNamespaceOptional = [];

  List<String> validSelfKeys = [];
  List<String> invalidSelfKeysNamespaceMandatory = [];
  List<String> invalidSelfKeysNamespaceOptional = [];

  List<String> validCachedPublicKeys = [];
  List<String> invalidCachedPublicKeysNamespaceMandatory = [];
  List<String> invalidCachedPublicKeysNamespaceOptional = [];

  List<String> validCachedSharedKeys = [];
  List<String> invalidCachedSharedKeysNamespaceMandatory = [];
  List<String> invalidCachedSharedKeysNamespaceOptional = [];

  TestKeys({bool includeNonBobKeys = true}) {
    _init(includeNonBobKeys);
  }

  _init(bool includeNonBobKeys) {
    _initValidPublicKeys();
    _initInvalidPublicKeys();

    _initValidPrivateKeys();
    _initInvalidPrivateKeys();

    _initValidCachedPublicKeys();
    _initInvalidCachedPublicKeys();

    _initValidSelfKeys();
    _initInvalidSelfKeys();

    _initValidSharedKeys();
    _initInvalidSharedKeys();

    _initValidCachedSharedKeys();
    _initInvalidCachedSharedKeys();

    if (includeNonBobKeys) {
      _initNonBobPublicKeys();
      _initNonBobPrivateKeys();
      _initNonBobCachedPublicKeys();
      _initNonBobSelfKeys();
      _initNonBobSharedKeys();
      _initNonBobCachedSharedKeys();
    }
  }

  _initNonBobPublicKeys() {
    // public key with max of 55 characters for the @sign
    validPublicKeys.add(
        "public:phone.buzz@bob0123456789012345678901234567890123456789012345");
    // public key with valid punctuations in the @sign
    validPublicKeys.add("public:phone.buzz@jagann_a-d_h");
    // public key with emoji's in @sign
    validPublicKeys.add("public:phone.buzz@bob💙");
    // Emojis in both @sign and entity
    validPublicKeys.add("public:phone😀.buzz@bob💙");

    // More than 55 characters for the @sign
    List<String> temp = [];
    temp.add(
        "public:phone.buzz@bob0123456789012345678901234567890123456789012345extrachars");
    //  Invalid punctuations in the @sign
    temp.add("public:phone.buzz@bo#b");
    //  Invalid and valid punctuations in the @sign
    temp.add("public:phone.buzz@jagan_____na#dh💙");
    //  sharedWith as well as public (must be one or the other, can't be both)
    temp.add("public:@bob:phone.buzz@jagan_____na#dh💙");
    //  more than one colon after 'public'
    temp.add("public::phone.buzz@jagan_____na#dh💙");
    //  colon in the entity fragment
    temp.add("public::foo.b:ar.buzz@jagan_____na#dh💙");
    //  colon before sharedBy
    temp.add("public:phone.buzz:@jagan_____na#dh💙");
    //  colon in sharedBy
    temp.add("public:phone.buzz@jag:an_____na#dh💙");
    //  colon at end of sharedBy
    temp.add("public:phone.buzz@jagan_____na#dh💙:");

    invalidPublicKeysNamespaceMandatory.addAll(temp);
    invalidPublicKeysNamespaceOptional.addAll(temp);
  }

  _initValidPublicKeys() {
    //  simple public key
    validPublicKeys.add("public:phone.buzz@bob");
    //  public key with single character entity and namespace
    validPublicKeys.add("public:p.b@bob");
    //  public key with punctuations in the entity name
    validPublicKeys.add("public:pho_-ne.b@bob");
    //  public key with single character entity and namespace
    validPublicKeys.add("public:p.b@bob");
    //  public key with punctuations in the entity name
    validPublicKeys.add("public:pho_-ne.b@bob");
    // public key with many punctuations in the entity name
    validPublicKeys.add("public:pho_-n________e.b@bob");
    //  public key with emoji's in entity
    validPublicKeys.add("public:phone😀.buzz@bob");
  }

  _initInvalidPublicKeys() {
    List<String> temp = [];
    // Misspelt public
    temp.add("publicc:phone.buzz@bob");
    //  sharedWith as well as public (must be one or the other, can't be both)
    temp.add("public:@bob:phone.buzz@bob");
    //  No public
    temp.add("phone.buzz@bob");
    //  No public and start with a :
    temp.add(":phone.buzz@bob");
    //  Invalid punctuations in the entity name
    temp.add("public:pho#ne.b@bob");
    // Valid and invalid punctuations together
    temp.add("public:pho#n____-____e.b@bob");
    // Key with no atsign
    temp.add("public:pho#n____-____e.b");
    // key without entity or owner
    temp.add("public:");
    // key without owner
    temp.add("public:foo.bar");
    // key without owner
    temp.add("public:foo.bar@");
    // key without entity
    temp.add("public:@bob");
    // multiple colons
    temp.add("public::@bob");
    // colon prefixed
    temp.add(":public:foo.bar@bob");

    invalidPublicKeysNamespaceMandatory.addAll(temp);
    invalidPublicKeysNamespaceOptional.addAll(temp);

    //  No namespace
    invalidPublicKeysNamespaceMandatory.add("public:phone@bob");
  }

  _initNonBobPrivateKeys() {
    // private key with max of 55 characters for the @sign
    validPrivateKeys.add(
        "private:@bob0123456789012345678901234567890123456789012345:phone.buzz@bob0123456789012345678901234567890123456789012345");
    //  private key with valid punctuations in the @sign
    validPrivateKeys.add("private:@jagann_a-d_h:phone.buzz@jagann_a-d_h");
    //  private key with emoji's in @sign
    validPrivateKeys.add("private:@bob💙:phone.buzz@bob💙");
    // 1Emoji in both @sign and entity
    validPrivateKeys.add("private:@bob💙:phone😀.buzz@bob💙");

    List<String> temp = [];
    //  Invalid punctuations in the @sign
    temp.add("private:@bo#b:phone.buzz@bo#b");
    //  Invalid and valid punctuations in the @sign
    temp.add("private:@jagan_____na#dh💙:phone.buzz@bob💙");

    invalidPrivateKeysNamespaceMandatory.addAll(temp);
    invalidPrivateKeysNamespaceOptional.addAll(temp);
  }

  _initValidPrivateKeys() {
    // private key with sharedWith specified
    validPrivateKeys.add("private:@bob:phone.buzz@bob");
    //  private key with sharedWith not specified
    validPrivateKeys.add("private:phone.buzz@bob");
    //  private key with sharedWith specified and single character entity and namespace
    validPrivateKeys.add("private:@bob:p.b@bob");
    //  private key with single character entity and namespace
    validPrivateKeys.add("private:p.b@bob");
    //  private key with punctuations in the entity name
    validPrivateKeys.add("private:pho_-ne.b@bob");
    // private key with many punctuations in the entity name
    validPrivateKeys.add("private:pho_-n________e.b@bob");
    //  private key with emoji's in entity
    validPrivateKeys.add("private:@bob:phone😀.buzz@bob");
  }

  _initInvalidPrivateKeys() {
    List<String> temp = [];
    // Misspelt private
    temp.add("privateeee:@bob:phone.buzz@bob");
    //  No private
    temp.add("phone.buzz@bob");
    //  No private and start with a :
    temp.add(":phone.buzz@bob");
    //  Invalid punctuations in the entity name
    temp.add("private:pho#ne.b@bob");
    // Valid and invalid punctuations together
    temp.add("private:pho#n____-____e.b@bob");
    // More than 55 characters for the @sign
    temp.add(
        "private:@bob0123456789012345678901234567890123456789012345extracharshere:phone.buzz@bob");

    invalidPrivateKeysNamespaceMandatory.addAll(temp);
    invalidPrivateKeysNamespaceOptional.addAll(temp);

    //  No namespace
    invalidPrivateKeysNamespaceMandatory.add("private:@bob:phone@bob");
  }

  _initNonBobCachedPublicKeys() {
    // cached public key with max of 55 characters for the @sign
    validCachedPublicKeys.add(
        "cached:public:phone.buzz@bob0123456789012345678901234567890123456789012345");
    //  cached public key with valid punctuations in the @sign
    validCachedPublicKeys.add("cached:public:phone.buzz@jagann_a-d_h");
    //  cached public key with emoji's in @sign
    validCachedPublicKeys.add("cached:public:phone.buzz@bob💙");
    // cached public public in both @sign and entity
    validCachedPublicKeys.add("cached:public:phone😀.buzz@bob💙");

    List<String> temp = [];
    //  Invalid and valid punctuations in the @sign
    temp.add("cached:public:phone.buzz@jagan_____na#dh💙");

    invalidCachedPublicKeysNamespaceMandatory.addAll(temp);
    invalidCachedPublicKeysNamespaceOptional.addAll(temp);
  }

  _initValidCachedPublicKeys() {
    // simple cached public key
    validCachedPublicKeys.add("cached:public:phone.buzz@bob");
    //  cached public key with single character entity and namespace
    validCachedPublicKeys.add("cached:public:p.b@bob");
    //  cached public key with single character entity and namespace
    validCachedPublicKeys.add("cached:public:p.b@bob");
    //  cached public key with punctuations in the entity name
    validCachedPublicKeys.add("cached:public:pho_-ne.b@bob");
    // cached public key with many punctuations in the entity name
    validCachedPublicKeys.add("cached:public:pho_-n________e.b@bob");
    //  cached public key with emoji's in entity
    validCachedPublicKeys.add("cached:public:phone😀.buzz@bob");
  }

  _initInvalidCachedPublicKeys() {
    List<String> temp = [];
    // Mis-spelt public
    temp.add("cached:publicc:phone.buzz@bob");
    //  sharedWith as well as public (must be one or the other, can't be both)
    temp.add("cached:public:@bob:phone.buzz@bob");
    //  No cached public
    temp.add("phone.buzz@bob");
    //  No cached public and start with a :
    temp.add(":phone.buzz@bob");
    //  Invalid punctuations in the entity name
    temp.add("cached:public:pho#ne.b@bob");
    // Valid and invalid punctuations together
    temp.add("cached:public:pho#n____-____e.b@bob");
    // More than 55 characters for the @sign
    temp.add(
        "cached:public:phone.buzz@bob0123456789012345678901234567890123456789012345extracharshere");
    //  Invalid punctuations in the @sign
    temp.add("cached:public:phone.buzz@@jaganna#dh");

    invalidCachedPublicKeysNamespaceMandatory.addAll(temp);
    invalidCachedPublicKeysNamespaceOptional.addAll(temp);

    //  No namespace
    invalidCachedPublicKeysNamespaceMandatory.add("cached:public:phone@bob");
  }

  _initNonBobSelfKeys() {
    // Self key with max of 55 characters for the @sign
    validSelfKeys.add(
        "@bob0123456789012345678901234567890123456789012345:phone.buzz@bob0123456789012345678901234567890123456789012345");
    //  Self key with valid punctuations in the @sign
    validSelfKeys.add("@jagann_a-d_h:phone.buzz@jagann_a-d_h");
    //  Self key with emoji's in @sign
    validSelfKeys.add("@bob💙:phone.buzz@bob💙");
    // 1Self key with emojis in both @sign and entity
    validSelfKeys.add("@bob💙:phone😀.buzz@bob💙");

    List<String> temp = [];
    // Invalid and valid punctuations in the @sign
    temp.add("@jagan_____na#dh💙:phone.buzz@bob💙");
    invalidSelfKeysNamespaceMandatory.addAll(temp);
    invalidSelfKeysNamespaceOptional.addAll(temp);
  }

  _initValidSelfKeys() {
    // Self key with shared with specified
    validSelfKeys.add("@bob:phone.buzz@bob");
    //  Self key with sharedWith not being specified
    validSelfKeys.add("phone.buzz@bob");
    //  Self key with sharedWith specified and single character entity and namespace
    validSelfKeys.add("@bob:p.b@bob");
    //  Self key with single character entity and namespace
    validSelfKeys.add("p.b@bob");
    //  Self key with punctuations in the entity name
    validSelfKeys.add("pho_-ne.b@bob");
    // Self key with many punctuations in the entity name
    validSelfKeys.add("pho_-n________e.b@bob");
    //  Self key with emoji's in entity
    validSelfKeys.add("@bob:phone😀.buzz@bob");
  }

  _initInvalidSelfKeys() {
    List<String> temp = [];
    //  Starts with a :
    temp.add(":phone.buzz@bob");
    //  Invalid punctuations in the entity name
    temp.add("@bob:pho#ne.b@bob");
    //  Valid and invalid punctuations together
    temp.add("@bob:pho#n____-____e.b@bob");
    //  More than 55 characters for the @sign
    temp.add(
        "@bob0123456789012345678901234567890123456789012345extracharshere:phone.buzz@bob");
    // Invalid punctuations in the @sign
    temp.add("@jaganna#dh:phone.buzz@bob");

    invalidSelfKeysNamespaceMandatory.addAll(temp);
    invalidSelfKeysNamespaceOptional.addAll(temp);

    // No namespace
    invalidSelfKeysNamespaceMandatory.add("@bob:phone@bob");
  }

  _initNonBobSharedKeys() {
    // Shared key with max of 55 characters for the @sign
    validSharedKeys.add(
        "@alice0123456789012345678901234567890123456789012345:phone.buzz@bob");
    // Shared key with valid punctuations in the @sign
    validSharedKeys.add("@sita_ram:phone.buzz@jagann_a-d_h");
    //  Shared key with emoji's in @sign
    validSharedKeys.add("@alice💙:phone.buzz@bob💙");
    //  Shared key with emojis in both @sign and entity
    validSharedKeys.add("@alice💙:phone😀.buzz@bob💙");

    List<String> temp = [];
    // Invalid and valid punctuations in the @sign
    temp.add("@sita_____ra#m💙:phone.buzz@bob💙");

    invalidSharedKeysNamespaceMandatory.addAll(temp);
    invalidSharedKeysNamespaceOptional.addAll(temp);
  }

  _initValidSharedKeys() {
    // Shared key with shared with specified
    validSharedKeys.add("@alice:phone.buzz@bob");
    //  Shared key with sharedWith specified and single character entity and namespace
    validSharedKeys.add("@alice:p.b@bob");
    //  Shared key with single character entity and namespace
    validSharedKeys.add("@alice:p.b@bob");
    //  Shared key with punctuations in the entity name
    validSharedKeys.add("@alice:pho_-ne.b@bob");
    //  Shared key with many punctuations in the entity name
    validSharedKeys.add("@alice:pho_-n________e.b@bob");
    //  Shared key with emoji's in entity
    validSharedKeys.add("@alice:phone😀.buzz@bob");
  }

  _initInvalidSharedKeys() {
    List<String> temp = [];
    //  Starts with a :
    temp.add(":phone.buzz@bob");
    //  Invalid punctuations in the entity name
    temp.add("@alice:pho#ne.b@bob");
    //  Valid and invalid punctuations together
    temp.add("@alice:pho#n____-____e.b@bob");
    //  More than 55 characters for the @sign
    temp.add(
        "@alicemm0123456789012345678901234567890123456789012345extracharshere:phone.buzz@bob");
    // Invalid punctuations in the @sign
    temp.add("@sita#ram:phone.buzz@bob");

    invalidSharedKeysNamespaceMandatory.addAll(temp);
    invalidSharedKeysNamespaceOptional.addAll(temp);

    // No namespace
    invalidSharedKeysNamespaceMandatory.add("@alice:phone@bob");
  }

  _initNonBobCachedSharedKeys() {
    // Cached shared key with valid punctuations in the @sign
    validCachedSharedKeys.add("cached:@sita_ram:phone.buzz@jagann_a-d_h");
    //  Cached shared key with emoji's in @sign
    validCachedSharedKeys.add("cached:@alice💙:phone.buzz@bob💙");
    //  Cached shared key with emojis in both @sign and entity
    validCachedSharedKeys.add("cached:@alice💙:phone😀.buzz@bob💙");

    List<String> temp = [];
    // Invalid and valid punctuations in the @sign
    temp.add("cached:@sita_____ra#m💙:phone.buzz@bob💙");

    invalidCachedSharedKeysNamespaceMandatory.addAll(temp);
    invalidCachedSharedKeysNamespaceOptional.addAll(temp);
  }

  _initValidCachedSharedKeys() {
    // Cached shared key with shared with specified
    validCachedSharedKeys.add("cached:@bob:phone.buzz@alice");
    // Cached shared key with sharedWith specified and single character entity and namespace
    validCachedSharedKeys.add("cached:@bob:p.b@alice");
    //  Cached shared key with single character entity and namespace
    validCachedSharedKeys.add("cached:@bob:p.b@alice");
    //  Cached shared key with punctuations in the entity name
    validCachedSharedKeys.add("cached:@bob:pho_-ne.b@alice");
    //  Cached shared key with many punctuations in the entity name
    validCachedSharedKeys.add("cached:@bob:pho_-n________e.b@alice");
    // Cached shared key with max of 55 characters for the @sign
    validCachedSharedKeys.add(
        "cached:@alice0123456789012345678901234567890123456789012345:phone.buzz@alice");
    //  Cached shared key with emoji's in entity
    validCachedSharedKeys.add("cached:@alice:phone😀.buzz@alice");
  }

  _initInvalidCachedSharedKeys() {
    List<String> temp = [];
    //  Starts with a :
    temp.add(":phone.buzz@bob");
    //  Invalid punctuations in the entity name
    temp.add("cached:@alice:pho#ne.b@bob");
    //  Valid and invalid punctuations together
    temp.add("cached:@alice:pho#n____-____e.b@bob");
    //  More than 55 characters for the @sign
    temp.add(
        "cached:@alicemm0123456789012345678901234567890123456789012345extracharshere:phone.buzz@bob");
    // Invalid punctuations in the @sign
    temp.add("cached:@sita#ram:phone.buzz@bob");

    invalidCachedSharedKeysNamespaceMandatory.addAll(temp);
    invalidCachedSharedKeysNamespaceOptional.addAll(temp);

    // No namespace
    invalidCachedSharedKeysNamespaceMandatory.add("cached:@alice:phone@bob");
  }
}
