enum PlaybackEngineKind {
  mpvTexture('mpv'),
  mpvNativeWindow('mpv（原生窗口）'),
  aether('AetherEngine'),
  media3('Media3');

  const PlaybackEngineKind(this.label);

  final String label;
}
