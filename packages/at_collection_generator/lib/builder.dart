import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'src/at_collection_generator_base.dart';


Builder atCollectionGenerator(BuilderOptions options) => 
  SharedPartBuilder([AtCollectionGenerator()],'at_collection_annotation');