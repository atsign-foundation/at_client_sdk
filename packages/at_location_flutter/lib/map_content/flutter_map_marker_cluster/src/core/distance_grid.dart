import 'dart:math';

class DistanceGrid<T> {
  final num cellSize;

  final num _sqCellSize;
  final Map<num, Map<num, List<T>>> _grid = {};
  final Map<T, Point> _objectPoint = {};

  DistanceGrid(this.cellSize) : _sqCellSize = cellSize * cellSize;

  void addObject(T obj, Point point) {
    var x = _getCoord(point.x), y = _getCoord(point.y);
    var row = _grid[y] ??= {};
    var cell = row[x] ??= [];

    _objectPoint[obj] = point;

    cell.add(obj);
  }

  void updateObject(T obj, Point point) {
    removeObject(obj);
    addObject(obj, point);
  }

  //Returns true if the object was found
  bool removeObject(T obj) {
    var point = _objectPoint[obj];
    if (point == null) return false;

    var x = _getCoord(point.x), y = _getCoord(point.y);
    var row = _grid[y] ??= {};
    var cell = row[x] ??= [];

    _objectPoint.remove(obj);

    for (var i = 0, len = cell.length; i < len; i++) {
      if (cell[i] == obj) {
        cell.removeAt(i);

        if (len == 1) {
          row.remove(x);

          if (_grid[y]!.isEmpty) {
            _grid.remove(y);
          }
        }

        return true;
      }
    }
    return false;
  }

  void eachObject(Function(T) fn) {
    for (var i in _grid.keys) {
      var row = _grid[i]!;

      for (var j in row.keys) {
        var cell = row[j]!;

        for (var k = 0, len = cell.length; k < len; k++) {
          fn(cell[k]);
        }
      }
    }
  }

  T? getNearObject(Point point) {
    var x = _getCoord(point.x),
        y = _getCoord(point.y),
        closestDistSq = _sqCellSize;
    T? closest;

    for (var i = y - 1; i <= y + 1; i++) {
      var row = _grid[i];
      if (row != null) {
        for (var j = x - 1; j <= x + 1; j++) {
          var cell = row[j];
          if (cell != null) {
            for (var k = 0, len = cell.length; k < len; k++) {
              var obj = cell[k];
              var dist = _sqDist(_objectPoint[obj]!, point);

              if (dist < closestDistSq ||
                  dist <= closestDistSq && closest == null) {
                closestDistSq = dist;
                closest = obj;
              }
            }
          }
        }
      }
    }
    return closest;
  }

  num _getCoord(num x) {
    var coord = x / cellSize;
    return coord.isFinite ? coord.floor() : x;
  }

  num _sqDist(Point p1, Point p2) {
    var dx = p2.x - p1.x, dy = p2.y - p1.y;
    return dx * dx + dy * dy;
  }
}
