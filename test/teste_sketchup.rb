# encoding: UTF-8
# Testa a integração com o SketchUp (main.rb) usando a API simulada.
require_relative 'apoio'
require_relative 'mock_su'
require File.join(SRC, 'main')

$falhas = 0
def confere(desc, ok)
  puts "#{ok ? 'OK   ' : 'FALHA'} #{desc}"
  $falhas += 1 unless ok
end

pol = lambda { |*c| c.map { |x, y, z| Geom::Point3d.new(x / 25.4, y / 25.4, z / 25.4) } }
v = [[0, 0, 0], [250, 0, 0], [250, 500, 0], [0, 500, 0],
     [0, 0, 3000], [250, 0, 3000], [250, 500, 3000], [0, 500, 3000]]
faces = [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]
ents = faces.map { |f| Sketchup::Face.new(pol.call(*f.map { |i| v[i] })) }
[[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4],
 [0, 4], [1, 5], [2, 6], [3, 7]].each { |i, j| ents << Sketchup::Edge.new(*pol.call(v[i], v[j])) }
alca = Sketchup::Definition.new('Alça de içamento#2',
                                [Sketchup::Edge.new(*pol.call([125, 350, 1000], [125, 600, 1000]))])
ents << Sketchup::ComponentInstance.new(alca, Sketchup::Layer.new('10. Insertos'))
defn = Sketchup::Definition.new('PV1', ents)
tag = Sketchup::Layer.new('2. Pilares')
inst = [Sketchup::ComponentInstance.new(defn, tag),
        Sketchup::ComponentInstance.new(defn, tag, Geom::Transformation.translation([100, 0, 0]))]
raiz = Sketchup::ComponentInstance.new(Sketchup::Definition.new('raiz', inst), Sketchup::Layer.new('Layer0'))

core = DetalhamentoPM::Core
cfg = core.cfg_prancha
pecas = core.coletar([raiz], cfg[:tags])
confere('coleta as 2 instâncias pela tag', pecas.size == 2)
tipos = core.agrupar(pecas, cfg)
t = tipos.first
confere('agrupa peças iguais (1 tipo, qtd 2)', tipos.size == 1 && t[:qtd] == 2)
confere('tipo PILAR pela tag', t[:tipo] == 'PILAR')
confere('dimensões em mm', t[:dims].map(&:round) == [250, 500, 3000])
confere('inserto separado do concreto', t[:insertos].map { |i| i[:nome] } == ['Alça de içamento'])

[0, 1, 2, 3].each do |f|
  dir = File.join(SAIDA, "formato#{f}")
  Dir.mkdir(dir) unless Dir.exist?(dir)
  feitas, erros = core.gerar_arquivos(tipos, cfg.merge(formato: f), dir)
  confere("formato #{core::FORMATOS[f]} sem erros", erros.empty? && !feitas.empty?)
end

puts($falhas.zero? ? 'Todos os testes passaram.' : "#{$falhas} teste(s) falharam.")
exit($falhas.zero? ? 0 : 1)
