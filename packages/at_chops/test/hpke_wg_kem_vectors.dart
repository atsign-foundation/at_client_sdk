/// The IETF HPKE working group's published test vectors for **KEM id 0x647A**,
/// the hybrid ML-KEM-768 + X25519 construction this package implements.
///
/// ## Why these exist alongside [XWingVector1]
///
/// [XWingVector1] comes from `draft-connolly-cfrg-xwing-kem-10` Appendix C, an
/// unadopted Independent Submission that CFRG never took up and that **expires
/// on 2026-09-03**. Its own appendix is titled "Test vectors # TODO: replace
/// with test vectors that re-use ML-KEM, X25519 values", so its authors mark it
/// provisional.
///
/// These come instead from the IETF **HPKE working group**, which registered
/// this construction at IANA HPKE KEM id `0x647A` and publishes
/// machine-readable vectors for it. `draft-irtf-cfrg-concrete-hybrid-kems`
/// section 4.2 states that its `MLKEM768-X25519` "is identical to the X-Wing
/// construction", retaining the same combiner label for compatibility, so
/// these exercise exactly the construction implemented here under a citation
/// that does not lapse.
///
/// They also cover all three KEM operations — key generation from [skRm],
/// derandomised encapsulation from [ikmE], and decapsulation of [enc] — so
/// they supersede the draft vector rather than merely supplementing it.
///
/// Naming caution: the IANA registry row still reads **X-Wing** (referencing
/// `draft-connolly-cfrg-xwing-kem-06`). `draft-ietf-hpke-pq-05` *requests* the
/// rename to `MLKEM768-X25519`; that request has not been effected, so the code
/// point should not be described as registered under the new name.
///
/// ## Provenance
///
/// Generated on 2026-08-06 from
/// <https://raw.githubusercontent.com/hpkewg/hpke-pq/main/test-vectors.json>
/// (13 vectors; exactly 2 carry `kem_id: 25722` = 0x647A, both mode 0). Go's
/// standard library vendors the same file at
/// `src/crypto/hpke/testdata/hpke-pq.json` and the two copies are
/// content-identical, so Go 1.26's `crypto/hpke.MLKEM768X25519()` is an
/// independent oracle for the same bytes.
///
/// Only the KEM-level fields are used; the rest of each row exercises the
/// RFC 9180 key schedule, which `rfc9180_hpke.dart` covers directly. Both rows
/// are `aead_id: 3` (ChaCha20-Poly1305);
/// there is no AES-GCM row at this KEM.
///
/// `ikmR` is deliberately absent: HPKE derives `skRm` from it via a
/// `DeriveKeyPair` step that takes input keying material, where this package
/// takes the 32-byte seed directly. [skRm] is that seed.
library;

import 'dart:typed_data';

import 'x_wing_test_vectors.dart' show fromHex;

/// One HPKE working-group KEM vector: the receiver keypair, an encapsulation
/// against it, and the shared secret that encapsulation yields.
class HpkeWgKemVector {
  /// The KDF id of the row this came from. Recorded for traceability only —
  /// the KEM output is independent of the KDF.
  final int kdfId;

  /// 32-byte receiver secret key, used here directly as the X-Wing seed.
  final Uint8List skRm;

  /// 1216-byte receiver public key (`pk_M || pk_X`).
  final Uint8List pkRm;

  /// 64-byte encapsulation randomness: `[0:32]` is the ML-KEM-768 randomness
  /// `m`, `[32:64]` the ephemeral X25519 secret. Feeds `encapsulateDerand`.
  final Uint8List ikmE;

  /// 1120-byte encapsulation (`ct_M || ct_X`).
  final Uint8List enc;

  /// 32-byte shared secret both `encapsulateDerand(pkRm, ikmE)` and
  /// `decapsulate(skRm, enc)` must produce.
  final Uint8List sharedSecret;

  const HpkeWgKemVector({
    required this.kdfId,
    required this.skRm,
    required this.pkRm,
    required this.ikmE,
    required this.enc,
    required this.sharedSecret,
  });
}

/// Both published `kem_id: 0x647A` rows.
final List<HpkeWgKemVector> hpkeWgKem0x647aVectors = [
  HpkeWgKemVector(
    kdfId: 1,
    skRm: fromHex(
        'b6bfa0299b955e85224df2e468f29eeab377ff3b96d4462b39447a22d32b91be'),
    pkRm: fromHex('''
      d3d102410970b8bab2984008669914490c95dea2c2ae331ca229aaf3609a6d5acbd60a9ecdd71c
      d462c08300c474e318b554675679b6d4e1bb1a76269a7a87e68335ba54593239290f35b65e5aa0
      d3352933339336e83260125e10ac21c97b40cff8385a18b2b7d62436377a13b00c27d22fea4176
      ff76ab80970ff0e26101c245b7c33dcaa420da8ab4df41b88985c6f3845e5a5364e7d7a74ae764
      c175bd462017cbbc5f684a7e4494391d050b83ba9ba66347774c707658c5cfe481a8c20efc6703
      14d7569a4793625abfd6579435b31886f80924c88c9a4011a0c58b6fe85c5330ca27aa80ffcc58
      d3ac6a759897b44893bf8b520802b4d7d56bc24976ba32c070f0cc7fd88c19e958de0b8fe93a76
      69b5bb8cf80a88e6aa827924cb1659fe6177023611ddd30eb913ad8b2c08fc8209bb9719c61450
      518881ca5b12b8c73ba3c27824773b5ec6571df41b277555d9aa8f566444614a8473d3b1a5e997
      af066ae1f355338302952281c82ba94f50a22e9ba55a56193d1a3f4b5365f7eb2ca81cb4573c33
      d1d9861cac8d4cf327c0393ab0c0b02572bbc3821bedb45d40257e1f7643796786fcf50126eb13
      6b35737794168a15643973639f6b6f3dd945d3ac6a5ab96e5d4b8fdcc54809053828610ee3a56b
      f4c84447147a9ca5745d5c05e3d9cfa659bb4c4c8f2e006826c27633a120c32151deaa2a98bc95
      78232b518604a5186fc7ac6a1e594b09106418eb1aa1ec6b44fabeae5105d75531b9279b07f627
      7ab297a5ea77d2383154bcb9db8a08fbb10522987d63c99958a774160333f5f208567a311464b5
      9ebb8cc8375a1f02470de68bad55c8e5184c8c4a0dcd45bfb59995f4c48ecf947896126830818a
      ca48c0749c057b6591d381922d8bb593e09d4bb7b6b046179c16a1d6b4149fb1cee31b6b9a015c
      ca526cfac8bf060c699e751c9456c26d832d58926032bb78ffa44d0d024f7a417e1b452f1f779d
      49c86e0784ab97686acb025c90f9893cc13bfc9186f0e9946ba498eb15a6684828bc0ca91482ce
      91dc4c12d0ce4b936e2556aebdc48cede6adcc066e78895086b49316725d9a0987ca75a7e00b0b
      be909397389fead7a8ff73bf94bb4272b27b9354bdbf3777a978024d074a45077ed0435b8b845e
      4481139b39ad1276973fd1cd8b1cc6e27b16998a7d6295c98347998d6669b15270dba7c098f161
      36015bd3b1c5897b1312f230e49bc07476cf4deb5bf0c971d5ac37f980283940c4e52999c549ae
      d09681a7f350f5a1bb1dd5a3b8837a22d506eb2029146817ec955d9dbc2939514ecf468c4eeb85
      198230effac612fb73348b42bcb9b27d9816a16596fb3618e71bcc321a4523a66ca248ac032c06
      b9e24cb084c59bc489868639ae7533f8f03a4eeb56f8a3568f687f38f83fbe163673eb76275b79
      d7f32a9109c30eaa96a0f622503c0337801fd9b2007603ce73c0378b250c35b634b6c8ac2cec1f
      bb24561a7a7812e77b4844bf9c6a299b409303c85199ca5dc6eac4e4f85ff10a464d96c7138276
      0af67fdf006c4eb6b627861d5bf1978588c02825ac70206274742af05a0dd136c2d465ac90b429
      3d05381d5911dcf48a878a6cf8d971d62c14700867e91dd050f85d68c32e227e5be68d3de02960
      8179f6f83b95e5deb6263fc01c80641763ebe08e7add5686b0ed1d1e7053982aa616130939d0a0
      9462df7dc74d05
'''),
    ikmE: fromHex('''
      c82228383c9fb887f7d8b332c28262024eda5b6b0ecd2325fe662daffc0594fad4990e7c8d1381
      2137d06ba7017453de675ab0388d418853617f3ca58cc5daf3
'''),
    enc: fromHex('''
      ab354dd589f74ee0eab7718a630cbec5df1d09058e177cd6dd141d883450ddd70c050d88bed3d0
      7cce23415cab411108cc30906482a71adcb134a56e978a6152a8e063b24acd1534f264f1045815
      2a9ed4f1f32b3d480c4f2453b7fdea7720146b3ee92cf8a13a4840076f68c911c65fa3db5053fb
      0aabf79e64cd5e7aa71b2b9641e713ec7df552e17d5020f8721ee449b42c888e2a3f87cfd96e3a
      98c3e7c4cd8f647f899570f596bf17d2b6fa2cad19706d9cc3cf09493e1c7ffa0eb2a4559ae1d9
      40fdbef97bed383e6ccfdb448d9f1a81805166b32c2af2e16878c6dc46ab43323ed9c136b92523
      9782e3c329c31a5cf2a80faf025a80766e244605c27afe4b624d9d8ca99b6ef5439ed1ad044b51
      8c434385acd49f1369ded6624a2832a571ccdd70d08b3c04cb1cd3136166f9a485f536f69ec66f
      0293e840025ccaac42f8e5f7c9cb818076c272797047f5e50c1e9f1dab81cfb48fe4c4998b2427
      f009702b145f34ad8dbc3e7ad4e4023057ba31cd02c4c0545ebf71eb02533e8eaa2b2f2690ee14
      07bf1f66dc5f4d836c45b82f10b720df72d237488a9af1b6dfb4741fd613379c2e211e77f7fae6
      b3734ad81de2d452005334857c4a3cbc82afc7428fe510495969b296d24e1a7431f557d48578cf
      92ae86c0392f0ba73755a9e5465c8e3495e4cd2a82d463244341e39414e26c9b242f31d2cf0e46
      b2aeb11dd5e56ec44834350d151344229e410faff2b2ace5c9b3fa12571db1d28da2c713349278
      1dac41b7a7e2bac2260fd12f56939033587824c9dfb17d41b3bceea53763193abe0c7c184d5de1
      61ef5312f31fab42478c9a193b868e4d29b2b7624f3ebe740f393d03d843cd5327286a579fd2a6
      e37aca5b64f9316115d612c7781e704ea7d182701c5019975cad14fbf4ab3904d4a35acaf0be32
      d716a1ef5d7188fc418ae9e60744325a3e8001655b756df94c24031c3ce32bd90c0ecdac52ca14
      0fdad7f44d04bd0a7e2a726c54cf9793f8784a23296f65da3fd1cbc18300d503c5b27be99b9b0e
      32d20b3614dc8a999f30c2779dd7886cfd486dc1c93ebcf517b5210a4359d9fa1805381f0f2261
      ff47de01de555d98bc1a30dda557a83007b61636abaf9041f96890f0f565eefc45859fbcd32d91
      b203215541227a4fcc3d95be2ddb0702878caa20f2da62c4ff9fe33af591ba1ec241fbe2208e04
      80f8b1cca1679c096f8f5a02a33e9df445b3274ac112b43d51510135cd3f532a3379e90bb7f0cb
      43717e90555bb1a80924cc69577455687cceb9b1610c05839541e87ad83d79ef3ff24ace1934cf
      be989691959d93ac48c716b672b370dd4c144ca1e32508707a6ef8aa29b55759b3d054c56bee1b
      aa6f41b84b9fc3fd681a1a1528eac578141529836a29dda1501a49ba2455367256d2fe6f74ebb7
      4ef9a49a94a4c6cd1dd09810f0e9bffa69dd8c94d226d0b2977b11a35382888961004a44c60fd6
      02e9ff4271287e9240ba96146515b9db9da60375aeeafeac1eeb764faebacd197df27817c35fe4
      c5c802e43349d7bc95c8b40c001449d3251c1d92ff6d5c3b08c4b27c
'''),
    sharedSecret: fromHex(
        'e059d39125d1f09a7232413a13ec5cb18a37417675442c962700d59da46d105a'),
  ),
  HpkeWgKemVector(
    kdfId: 17,
    skRm: fromHex(
        'ade62d76461f5fb35b5de3419f10b4ab4cfd81512da8e8a094d51ad9746d9868'),
    pkRm: fromHex('''
      4b9531fb494a29413d0ab36a92c7749d5b409a137f1a05c1385a6818308bd3d32f1065b73cb9a2
      fe9b77e74b9bb71a4a1f0aa01568687cf413893951d5e983e39904d0f3ac2cf457297741cb2658
      123ac5b0116863356b4b55551c5bb56faa9c80a62417ea90dcd683601c5d2a977d0d74010f975c
      15622d01451d97234761c3c8ff185c37a11acfc0c5fb311b2660c7ec28438498475d2c2dea12ac
      0387ce3ec4669450302fca9a0ab93bd7cba2879c730bc17d6b5417c383c1f90b9807343322f85d
      89abb16686bdf82176b7b36284678f017990ba4a724e36013bb38e5cc762c6e8c4127536b44659
      e9890608d2bd355148d5e3024842011c800c5ff72e20da517aa669c1c78ec5a727129692ddec53
      d4d5aaa35016d63482d0a835977ca0bff350ebf7b4317259d25a03511abcc5d631c979cb1c18bb
      829c257dcb038c5085105aa88e5744e9507a247877796693f1631469f29dfab7a5d1ccb818c03f
      f652c4a896b9aa9264192b2f316973eca345c1f29ad6d9004e6a76afec630208ad6bc058eeb81a
      1380ce567b57ec24a1f4c725611591e85a8bd0d8a306e32fa7002fdb4c9ac9d02c73f557bb9c0a
      5f55295c33b9adbc4469a6a321eb39dbdb13fd44a556200e33184fa44346741c12fe097b22c778
      fa25681d954da3843a609a1ccf38478658883bfa6b314b6b93e11105884a59968a3cf89beff471
      7db7ac938b89683bc588c6553389b53ca744099741f1d96e84ab93aeabb10e4b5d1269244fa93b
      5ff27298872346733e38c48e92f817e1e98c61c220a1069a3705810646463de7076c207d5d40b7
      dd812f58d8acf171900d7b8d9fc56f1c2929dbecb76580554ba6b0b0447a8f6a6028f4cbb1933a
      58a26186cc4671c8caa6286d9124cb53b82e12d90beb792cec4c556dac44c49a37dd49c2d42a91
      7578ac08a51699331c79babb43ec2a3647cc37db9316920693e194990baa7443a507104d3b62b0
      15a199432aa606b4613f8cc63bd0565d66ce41d59b273bb6cdb95ebdd255029cbf6f6221aba898
      f2a8868239975dd00c9a520b394849df134b318cb4e2b25fad4b0b92d0c742bb3bd0c8c98ca273
      9048277d4b2056f3063895613d0a06a3d9a3bb86cf47d8158d10cc6537008a7469f3fa0609604d
      896918e4676598232b30d9ca520ab308610f92d7b4cfbc3dcbe14cf90c925000501737a5b0f61f
      98006ecc7c21e934c547e4800d54b2b578c9b4f435eac666094720fd45862a07a0121c0971b57b
      3fb69dc2c4b47dfbb47504295cd58adca7c0da5244dd7550576545b214c93796a9c0458b3d8879
      47f8bfa88959e7f1c72821548eba7ea9f74a787c2b40b962ab58835a52524a94079a61284d7acb
      4943a54a117fc71b94776b732a644f66c451fbe34593a44d57fb21348799608959fad5c84e9909
      51aca92c8bc68e084d2d596307f586be8cb3e043507be17e70312156eb6e464cc530377d23f32a
      48fb6921ab320a324fefa807c3cb262c460d9c1c8a23c9314cc3847fccc66c9519ba2756f9956c
      edb8b42a38cd25f7237cc7ba5d50c8c2ac446fb7a4a76762c5f151d04682122057e793851a3496
      d5177782c4afe2688a7ae2a198156d0cdcb4c64c8d282661abe19ffc2ca793ee9a2c190c5c6852
      d1d743384730c92c1bd82d4333642a14f7e3cdd98b1791c98c1a09d3a0dd71b1e253cfc077801a
      0c2729f53a3023
'''),
    ikmE: fromHex('''
      ac9639cf4581ac270569ed0fd1f4ab0feb59db2956c91c38fd1744768102f69d29ad8d4e9fda60
      43676fa808d148fd448397fce724141dd9b8e9827d274a9fa5
'''),
    enc: fromHex('''
      b0e05d539064754e11737ec32a268888b7fd7ccc11cdb3465860b26e75a5976b1e586c83503332
      c395cc312278d3bd6a8118db9718397dec4bf7a7f0ddc1d9edc0d0072b5bd8fe4861d6a01022cb
      3f30bac913753c60ce38fe3c322d60ad4bdc41682b292bae49226e1b01736877d232034170046b
      4058111d12285c47b0a3efae9e59654d3a7ee637d4b2fb00f17bd9337bf98cb59acf2ae53db40c
      a11910bfb639b82b15d9fd4be09df8d5e7b3acafa9cd24df808ea8557e86c325d49387ac8b2b96
      16d1f76efb6fd026345077641d7fde4ad3a83ff10f67de3eb4ec48f3045ed2032c3a9ec9642cb7
      0bb7bc27d0b56f0a6b323506b8d25c412bfd25897f228122bafe2e5f8e55112c9f8e7c29d6d249
      8ace41742b7fd0e31a12afb2bf1beebcf63e387b0826e5a69594293dc2f241cf7dfa8cf2739168
      0f3d72e8c90fded4605058168ce313a9de059d1a7e34f8016e62f9c824f440245498f463420b77
      36446b8fba0f8848b00094cae0749d2f2fc6506511c7a43774eef264fb3f8b20c46f50e394a325
      dd2de4b92aeab2db9d8f29e7e547766ebcf78000a1d33a74d0738f693e6d2389f6b6ec90a608b5
      0f07608c417e10f6f7ba0f0e489faa6bb93b78a189ce8a02035857628c44f3edbdcb5b1a61c086
      4209b5bafb7ee9900605321505bcd6e1579f62ae97ada8c030ec7fb3591142348739b3aa3ceea9
      34b0f48619011301a2997f070de0a064cff27beb55543ba9447e6ac0e94dd171ac471ed3f773c4
      e34e9442c91da655db39895a2c4f290e900b0c3b37691363a1ac5c78db70750ee0ef54f80ef631
      cfd920d78ee1686f67536cbf1a74fe19f90c20eef96b02e4e34030a0ea833179d4ae5a6c17c423
      271b4ad59f9045453a876561275d93d82a87af02c15a5513d8537d954fb42db00edaabf8853840
      f00bc618432c6a9cd94b990549a35bdab4b1be7a101862a3e7aa36f24513314751b2a6648f7552
      a1672decbca45717098c6808f12f341139ab75b5af14f895359b1152f638a3cbaacdb355ecd1af
      2daa5ae121d2dc68c13713dd99f738e6c6d9c7409365dab6027ac1a7a71e0e6d2075a1593cae0a
      664ab04cb0ab0711b15a5836e1eb40323fb60477215fd40f9b6b52ac7b2e73dde487d729dbc3c7
      f976adbb28edcca8948b1a22f11943d367452e817f20ed27d4feb5341e4078164bb0010643d91f
      ad31aee0c446274cc511501ecd929f83e8489dc385cd1d2173a7e63791d5a7eb7d0115389e9a60
      4a999a2a9b443655876187cb060ea8bf5272fd06b85a33545ffd7ec6e76e866f6f58c9f3214f16
      125bd541cf0dd22a40042e19abc47462f7bee257958d330a74f6abc17c3dc1f23fd7da0b274eab
      80dd6691c94ed5694cfbbce7d25e3a37b94358b87b57777ebf82d9a852301e3353bf6356f26eb3
      d293ac97477b34734d7c1efaebfd2c22d7820ecff59b7da55ccd0f2a54e645064612b716736543
      948bfb20234ef9d5a61e0697d8abc940711632f56a14177de163c7d0b1788a0cb17272175ab893
      370766d75d28680cc2593902aafcc6ce2f25e3b71a9c1ff5f0871a0c
'''),
    sharedSecret: fromHex(
        'c3b302f7ad7e13ab4713facdd0d8058507133e966519acca3af01ab2d5c96549'),
  ),
];
