class MemoryLayer {
  final String id; 
  final String title; 
  final String description; 
  final double latitude; 
  final double longitude; 
  final double discoveryRadius;

  const MemoryLayer({
    required this.id, 
    required this.title, 
    required this.description, 
    required this.latitude, 
    required this.longitude,
    required this.discoveryRadius
  });
}