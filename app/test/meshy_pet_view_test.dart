import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/meshy_pet_view.dart';
import 'package:kopilych/pet_motion.dart';

void main() {
  test('3D clips use the names exported by the pet rigs', () {
    expect(PetAnimation.values.map((clip) => clip.name), [
      'idle',
      'walk',
      'feed',
      'play',
      'bath',
      'happy',
    ]);
    expect(PetAnimation.fromAction(PetAction.feed), PetAnimation.feed);
    expect(PetAnimation.fromAction(PetAction.play), PetAnimation.play);
    expect(PetAnimation.fromAction(PetAction.bath), PetAnimation.bath);
    expect(PetAnimation.fromAction(PetAction.love), PetAnimation.happy);
    expect(PetAnimation.fromAction(PetAction.celebrate), PetAnimation.happy);
  });

  test('each pet preview uses the species model for supported wearables', () {
    for (final species in [0, 1, 2]) {
      for (final wearable in [null, 'cap', 'bow']) {
        expect(MeshyPetView.assetFor(species, wearable), endsWith('.glb'));
      }
    }
    expect(MeshyPetView.assetFor(2, 'bow'), MeshyPetView.assetFor(2, null));
    expect(() => MeshyPetView.assetFor(2, 'unknown'), throwsArgumentError);
  });
}
