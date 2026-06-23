import 'package:echo/features/profile/domain/models/profile_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum ConnectionStatus {
  none,
  pendingSent,
  pendingReceived,
  connected,
  blocked,       // io ho bloccato loro
  blockedByThem; // loro hanno bloccato me

  static ConnectionStatus fromString(String s) {
    switch (s) {
      case 'connected':
        return ConnectionStatus.connected;
      case 'pending_sent':
        return ConnectionStatus.pendingSent;
      case 'pending_received':
        return ConnectionStatus.pendingReceived;
      case 'blocked':
        return ConnectionStatus.blocked;
      default:
        return ConnectionStatus.none;
    }
  }
}

class ConnectionRepository {
  final SupabaseClient _client;

  ConnectionRepository(this._client);

  Future<ConnectionStatus> getStatus(String targetUserId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Non autenticato');

    // Check if I blocked them.
    final block = await _client
        .from('blocked_users')
        .select('blocked_id')
        .eq('blocker_id', userId)
        .eq('blocked_id', targetUserId)
        .maybeSingle();
    if (block != null) return ConnectionStatus.blocked;

    // Check if they blocked me.
    final reverseBlock = await _client
        .from('blocked_users')
        .select('blocker_id')
        .eq('blocker_id', targetUserId)
        .eq('blocked_id', userId)
        .maybeSingle();
    if (reverseBlock != null) return ConnectionStatus.blockedByThem;

    final result = await _client.rpc(
      'get_connection_status',
      params: {'target_user_id': targetUserId},
    );
    return ConnectionStatus.fromString(result as String? ?? 'none');
  }

  Future<void> blockUser(String targetUserId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Non autenticato');
    // Remove any existing connection before blocking.
    await removeConnection(targetUserId);
    await _client.from('blocked_users').upsert({
      'blocker_id': userId,
      'blocked_id': targetUserId,
    });
  }

  Future<void> unblockUser(String targetUserId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Non autenticato');
    await _client
        .from('blocked_users')
        .delete()
        .eq('blocker_id', userId)
        .eq('blocked_id', targetUserId);
  }

  Future<void> sendRequest(String targetUserId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Non autenticato');
    await _client.from('connections').insert({
      'requester_id': userId,
      'target_id': targetUserId,
    });
  }

  Future<void> acceptRequest(String requesterUserId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Non autenticato');
    await _client
        .from('connections')
        .update({'status': 'accepted'})
        .match({'requester_id': requesterUserId, 'target_id': userId});
  }

  Future<void> removeConnection(String otherUserId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Non autenticato');
    await _client.from('connections').delete().or(
          'and(requester_id.eq.$userId,target_id.eq.$otherUserId),'
          'and(requester_id.eq.$otherUserId,target_id.eq.$userId)',
        );
  }

  Future<List<ProfileModel>> getMyConnections() async {
    final rows = await _client.rpc('get_my_connections');
    return (rows as List<dynamic>)
        .map((r) => ProfileModel.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<List<ProfileModel>> getPendingRequests() async {
    final rows = await _client.rpc('get_pending_requests');
    return (rows as List<dynamic>)
        .map((r) => ProfileModel.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<List<ProfileModel>> getBlockedUsers() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Non autenticato');

    final blocks = await _client
        .from('blocked_users')
        .select('blocked_id')
        .eq('blocker_id', userId);

    final ids = (blocks as List<dynamic>)
        .map((r) => r['blocked_id'] as String)
        .toList();

    if (ids.isEmpty) return [];

    final profiles = await _client
        .from('profiles')
        .select()
        .inFilter('id', ids);

    return (profiles as List<dynamic>)
        .map((r) => ProfileModel.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }
}
