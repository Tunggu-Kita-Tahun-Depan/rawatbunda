import '../models/clinical_document.dart';

abstract interface class DocumentRepository {
  Future<ClinicalDocument> save(ClinicalDocument document);

  Future<ClinicalDocument?> getById(String id);
}

class InMemoryDocumentRepository implements DocumentRepository {
  final Map<String, ClinicalDocument> _documents = {};

  @override
  Future<ClinicalDocument> save(ClinicalDocument document) async {
    _documents[document.id] = document;
    return document;
  }

  @override
  Future<ClinicalDocument?> getById(String id) async => _documents[id];
}
