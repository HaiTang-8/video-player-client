/// 一次播放的业务对象：电影或某一集
sealed class PlaybackItem {
  const PlaybackItem();
}

final class MoviePlaybackItem extends PlaybackItem {
  final int movieId;

  const MoviePlaybackItem(this.movieId);
}

final class EpisodePlaybackItem extends PlaybackItem {
  final int tvShowId;
  final int seasonId;
  final int episodeId;

  const EpisodePlaybackItem({
    required this.tvShowId,
    required this.seasonId,
    required this.episodeId,
  });
}
