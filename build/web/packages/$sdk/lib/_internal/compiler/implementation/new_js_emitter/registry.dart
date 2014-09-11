// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of dart2js.new_js_emitter.emitter;

/// A Fragment maps [LibraryElement]s to their [Element]s.
///
/// Fundamentally, this class is a `Map<LibraryElement, List<Element>>`.
class Fragment {
  final Map<LibraryElement, List<Element>> _mapping = <LibraryElement,
      List<Element>>{};

  // It is very common to access the same library multiple times in a row, so
  // we cache the last access.
  LibraryElement _lastLibrary;
  List<Element> _lastElements;

  void add(LibraryElement library, Element element) {
    if (_lastLibrary != library) {
      _lastLibrary = library;
      _lastElements = _mapping.putIfAbsent(library, () => <Element>[]);
    }
    _lastElements.add(element);
  }

  int get length => _mapping.length;

  void forEach(void f(LibraryElement library, List<Element> elements)) {
    _mapping.forEach(f);
  }
}

class Registry {
  final DeferredLoadTask _deferredLoadTask;
  final Map<String, Holder> _holdersMap = <String, Holder>{};
  final Map<OutputUnit, Fragment> _fragmentsMap = <OutputUnit, Fragment>{};

  Iterable<Holder> get holders => _holdersMap.values;
  Iterable<Fragment> get deferredFragments => _fragmentsMap.values.skip(1);
  int get fragmentCount => _fragmentsMap.length;

  /// A fastpath for `_libraryElements[_mainOutputUnit]`.
  final Fragment mainFragment = new Fragment();

  Registry(this._deferredLoadTask) {
    _fragmentsMap[_mainOutputUnit] = mainFragment;
  }

  bool get _isProgramSplit => _deferredLoadTask.isProgramSplit;
  OutputUnit get _mainOutputUnit => _deferredLoadTask.mainOutputUnit;

  Fragment _computeTargetFragment(Element element) {
    if (!_isProgramSplit) return mainFragment;
    OutputUnit targetUnit = _deferredLoadTask.outputUnitForElement(element);
    return (targetUnit == _mainOutputUnit)
        ? mainFragment
        : _fragmentsMap.putIfAbsent(targetUnit, () => new Fragment());
  }

  /// Adds the element to the list of elements of the library in the right
  /// fragment.
  void registerElement(Element element) {
    _computeTargetFragment(element).add(element.library, element);
  }

  Holder registerHolder(String name) {
    return _holdersMap.putIfAbsent(
        name,
        () => new Holder(name, _holdersMap.length));
  }
}