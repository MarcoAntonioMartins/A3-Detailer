# encoding: UTF-8
# Simulação mínima da API do SketchUp para testar main.rb fora do programa.
$LOADED_FEATURES << 'sketchup.rb'
$arquivos_carregados = {}
def file_loaded?(f) $arquivos_carregados[f] end
def file_loaded(f) $arquivos_carregados[f] = true end
MB_YESNO = 4
IDYES = 6

module Geom
  class Point3d
    attr_reader :x, :y, :z
    def initialize(x, y, z) @x, @y, @z = x.to_f, y.to_f, z.to_f end
    def transform(t) t.aplica(self) end
  end
  class Vector3d < Point3d
    def length; Math.sqrt(x * x + y * y + z * z) end
    def transform(t) t.aplica_vetor(self) end
  end
  class Transformation
    attr_reader :m, :o
    def initialize(m = [[1, 0, 0], [0, 1, 0], [0, 0, 1]], o = [0, 0, 0]) @m, @o = m, o end
    def self.scaling(a, b, c) new([[a, 0, 0], [0, b, 0], [0, 0, c]]) end
    def self.translation(v) new([[1, 0, 0], [0, 1, 0], [0, 0, 1]], v) end
    def aplica_vetor(p)
      v = [p.x, p.y, p.z]
      r = (0..2).map { |i| (0..2).map { |j| @m[i][j] * v[j] }.sum }
      Vector3d.new(*r)
    end
    def aplica(p)
      v = aplica_vetor(p)
      Point3d.new(v.x + @o[0], v.y + @o[1], v.z + @o[2])
    end
    def *(t)
      m = (0..2).map { |i| (0..2).map { |j| (0..2).map { |k| @m[i][k] * t.m[k][j] }.sum } }
      o2 = aplica(Point3d.new(*t.o))
      Transformation.new(m, [o2.x, o2.y, o2.z])
    end
  end
end

module Sketchup
  @prefs = {}
  def self.read_default(_s, k, pad) @prefs.fetch(k, pad) end
  def self.write_default(_s, k, v) @prefs[k] = v end
  def self.status_text=(_); end
  Layer = Struct.new(:name) do
    def visible?; true end
  end
  class Mesh
    def initialize(pts) @pts = pts end
    def count_points; @pts.size end
    def point_at(i) @pts[i - 1] end
    def polygons; (2...@pts.size).map { |k| [1, -k, k + 1] } end
  end
  class Face
    def initialize(pts) @pts = pts end
    def hidden?; false end
    def mesh(_f) Mesh.new(@pts) end
  end
  Vertex = Struct.new(:position)
  class Edge
    attr_reader :start, :end
    def initialize(a, b) @start, @end = Vertex.new(a), Vertex.new(b) end
    def hidden?; false end
    def soft?; false end
  end
  Definition = Struct.new(:name, :entities)
  class ComponentInstance
    attr_accessor :name, :definition, :layer, :transformation
    def initialize(defn, layer, t = Geom::Transformation.new)
      @name, @definition, @layer, @transformation = '', defn, layer, t
    end
    def hidden?; false end
    def volume; -1 end
  end
  class Group < ComponentInstance; end
end

module UI
  def self.menu(_) Menu.new end
  class Menu
    def add_submenu(_) self end
    def add_item(_) end
    def add_separator; end
  end
  def self.add_context_menu_handler; end
end
