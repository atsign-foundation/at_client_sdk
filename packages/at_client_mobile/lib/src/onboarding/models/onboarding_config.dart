enum DialogType {
  modal,
  sheet,
}

class OnboardingConfig {
  const OnboardingConfig({
    this.dialogType,
  });

  final DialogType? dialogType;
}
