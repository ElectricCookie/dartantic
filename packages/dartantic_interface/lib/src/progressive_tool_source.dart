import 'tool.dart';

class ProgressiveToolDescriptor {
  final String name;
  final String description;

  const ProgressiveToolDescriptor({
    required this.name,
    required this.description,
  });
}

abstract class ProgressiveToolSource {
  Future<List<ProgressiveToolDescriptor>> searchTools(String query);

  Future<Tool> getTool(String name);
}