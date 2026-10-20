import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bdk_audio/features/sound/widgets/preset_shape.dart';
void main(){
  testWidgets('mini preset curve fills available card width',(tester)async{
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:Align(alignment:Alignment.topLeft,child:SizedBox(width:160,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[PresetShape(key:const ValueKey('mini'),levels:[8,-1,-2])]))))));
    expect(tester.getSize(find.byKey(const ValueKey('mini'))).width,160);
  });
}
