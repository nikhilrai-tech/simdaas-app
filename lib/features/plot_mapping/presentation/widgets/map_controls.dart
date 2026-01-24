import 'package:flutter/material.dart';

/// Lightweight map search controls: text input + suggestion list.
class MapSearchControls extends StatelessWidget {
  final TextEditingController searchCtrl;
  final FocusNode searchFocus;
  final bool isSearching;
  final List<Map<String, dynamic>> searchSuggestions;
  final void Function(String) onSubmitted;
  final void Function(Map<String, dynamic>) onSuggestionTap;
  final void Function(String) onSearchIconPressed;

  const MapSearchControls({
    super.key,
    required this.searchCtrl,
    required this.searchFocus,
    required this.isSearching,
    required this.searchSuggestions,
    required this.onSubmitted,
    required this.onSuggestionTap,
    required this.onSearchIconPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: searchCtrl,
                  focusNode: searchFocus,
                  decoration: const InputDecoration(
                    hintText: 'Search location or lat,lng',
                    border: InputBorder.none,
                  ),
                  onSubmitted: (text) => onSubmitted(text.trim()),
                ),
              ),
              if (isSearching)
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                IconButton(
                  onPressed: () => onSearchIconPressed(searchCtrl.text.trim()),
                  icon: const Icon(Icons.search),
                ),
            ]),
          ),
        ),
        if (searchSuggestions.isNotEmpty)
          Card(
            elevation: 4,
            margin: const EdgeInsets.only(top: 4),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: searchSuggestions.length,
              itemBuilder: (context, index) {
                final suggestion = searchSuggestions[index];
                final displayName = suggestion['display_name'] as String;
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.location_on, size: 20),
                  title: Text(
                    displayName,
                    style: const TextStyle(fontSize: 14),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => onSuggestionTap(suggestion),
                );
              },
            ),
          ),
      ],
    );
  }
}
