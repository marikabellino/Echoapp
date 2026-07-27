import 'package:cached_network_image/cached_network_image.dart';
import 'package:echo/core/theme/app_colors.dart';
import 'package:echo/core/theme/app_radius.dart';
import 'package:echo/core/theme/app_text_styles.dart';
import 'package:echo/features/community/providers/connection_provider.dart';
import 'package:echo/features/profile/domain/models/profile_model.dart';
import 'package:echo/shared/widgets/echo_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─── Tag people sheet: multi-select dalla cerchia ─────────────────────────────
//
// Condiviso tra la creazione del drop (create_page.dart, dove il tag è
// ancora locale finché non si pubblica) e il tag su un drop già pubblicato
// (drop_feed_card.dart, dal menu opzioni "⋯"): in entrambi i casi si sceglie
// tra le persone della propria cerchia accettata.

class TagPeopleSheet extends ConsumerStatefulWidget {
  const TagPeopleSheet({
    super.key,
    this.initiallySelected = const [],
    this.excludeUserIds = const {},
  });

  /// Persone già selezionate quando lo sheet si apre (usato in create_page,
  /// dove si può riaprire il picker per modificare la selezione fatta finora).
  final List<ProfileModel> initiallySelected;

  /// Persone da non mostrare nella lista perché già taggate sul drop (usato
  /// quando si tagga un drop già pubblicato: la RPC tag_users_on_drop può
  /// solo aggiungere, non sostituire, quindi non ha senso poterle riselezionare).
  final Set<String> excludeUserIds;

  @override
  ConsumerState<TagPeopleSheet> createState() => _TagPeopleSheetState();
}

class _TagPeopleSheetState extends ConsumerState<TagPeopleSheet> {
  late final Map<String, ProfileModel> _selected = {
    for (final u in widget.initiallySelected) u.id: u,
  };
  String _query = '';

  void _toggle(ProfileModel user) {
    setState(() {
      if (_selected.containsKey(user.id)) {
        _selected.remove(user.id);
      } else {
        _selected[user.id] = user;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final connectionsAsync = ref.watch(myConnectionsProvider);

    return EchoBottomSheet(
      height: MediaQuery.of(context).size.height * 0.75,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  Text('Tagga persone', style: AppTextStyles.headline(context)),
                  const Spacer(),
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context).pop(_selected.values.toList()),
                    child: Text('Fatto (${_selected.length})'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: TextField(
                onChanged: (v) => setState(() => _query = v.trim()),
                style: AppTextStyles.body(context),
                decoration: InputDecoration(
                  hintText: 'Cerca nella tua cerchia',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
            ),
            Expanded(
              child: connectionsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => Center(
                  child: Text(
                    'Errore nel caricamento',
                    style: AppTextStyles.bodySecondary(context),
                  ),
                ),
                data: (allConnections) {
                  final connections = allConnections
                      .where((u) => !widget.excludeUserIds.contains(u.id))
                      .toList();
                  final filtered = connections.where((u) {
                    if (_query.isEmpty) return true;
                    final q = _query.toLowerCase();
                    return u.username.toLowerCase().contains(q) ||
                        u.displayName.toLowerCase().contains(q);
                  }).toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Text(
                        connections.isEmpty
                            ? 'Non hai ancora collegamenti da taggare.'
                            : 'Nessun utente trovato.',
                        style: AppTextStyles.bodySecondary(context),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final user = filtered[i];
                      final name = user.displayName.isNotEmpty
                          ? user.displayName
                          : user.username;
                      final checked = _selected.containsKey(user.id);
                      return ListTile(
                        onTap: () => _toggle(user),
                        leading: CircleAvatar(
                          radius: 20,
                          backgroundColor: AppColors.accent.withValues(
                            alpha: 0.15,
                          ),
                          backgroundImage: user.avatarUrl != null
                              ? CachedNetworkImageProvider(user.avatarUrl!)
                              : null,
                          child: user.avatarUrl == null
                              ? Text(
                                  name[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: AppColors.accent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : null,
                        ),
                        title: Text(name, style: AppTextStyles.body(context)),
                        subtitle: Text(
                          '@${user.username}',
                          style: AppTextStyles.bodySecondary(
                            context,
                          ).copyWith(fontSize: 12),
                        ),
                        trailing: Icon(
                          checked
                              ? Icons.check_circle_rounded
                              : Icons.circle_outlined,
                          color: checked
                              ? AppColors.accent
                              : Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.3),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
