import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexora/core/cache/datasources/media_local_data_source_impl.dart';
import 'package:nexora/core/cache/eviction/cache_eviction_service.dart';
import 'package:nexora/core/cache/repository/media_cache_repository.dart';
import 'package:nexora/core/cache/repository/media_cache_repository_impl.dart';
import 'package:nexora/core/cache/services/hive_cache_manager.dart';
import 'package:nexora/core/services/cloudinary_storage_services.dart';
import 'package:nexora/features/auth/services/supabase_auth_services.dart';
import 'package:nexora/features/comments/services/comments_service.dart';
import 'package:nexora/features/discover/services/discover_people_services.dart';
import 'package:nexora/features/group_calls/services/group_call_signaling_service.dart';
import 'package:nexora/features/group_chats/services/group_chat_services.dart';
import 'package:nexora/features/posts/services/posts_services.dart';
import 'package:nexora/features/profile/services/user_services.dart';
import 'package:nexora/features/single_calls/services/call_signaling_service.dart';
import 'package:nexora/features/single_chats/services/chat_presence_service.dart';
import 'package:nexora/features/single_chats/services/chat_services.dart';
import 'package:nexora/features/social_graph/services/connections_service.dart';
import 'package:nexora/features/social_graph/services/follow_services.dart';
import 'package:nexora/features/social_graph/services/friendship_services.dart';

class ServiceProviders {
  ServiceProviders._();

  static final all = [
    RepositoryProvider(create: (_) => SupabaseAuthServices()),
    RepositoryProvider(create: (_) => ConnectionsService()),
    RepositoryProvider(create: (_) => ChatServices()),
    RepositoryProvider(create: (_) => ChatPresenceService()),
    RepositoryProvider(create: (_) => GroupChatServices()),
    RepositoryProvider(create: (_) => CallSignalingService()),
    RepositoryProvider(create: (_) => UserService()),
    RepositoryProvider(create: (_) => CommentsService()),
    RepositoryProvider(create: (_) => PostsServices()),
    RepositoryProvider(create: (_) => CloudinaryStorageServices.instance),
    RepositoryProvider(create: (_) => DiscoverPeopleServices()),
    RepositoryProvider(create: (_) => FriendshipServices()),
    RepositoryProvider(create: (_) => FollowServices()),
    RepositoryProvider(create: (_) => GroupCallSignalingService()),
    RepositoryProvider<MediaCacheRepository>(
      create: (_) {
        final localDataSource = MediaLocalDataSourceImpl(
          box: HiveCacheManager.instance.mediaCacheBox,
          metaBox: HiveCacheManager.instance.cacheMetaBox,
        );

        final cacheEvictionService = CacheEvictionService(
          localDataSource: localDataSource,
          metaBox: HiveCacheManager.instance.cacheMetaBox,
        );
        return MediaCacheRepositoryImpl(
          localDataSource: localDataSource,
          evictionService: cacheEvictionService,
        )..initialize();
      },
    ),
  ];
}
