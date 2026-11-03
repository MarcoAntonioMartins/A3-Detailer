# encoding: UTF-8
# Detalhamento Pré-moldado - carregador da extensão
require 'sketchup.rb'
require 'extensions.rb'

module DetalhamentoPM
  unless file_loaded?(__FILE__)
    ext = SketchupExtension.new('Detalhamento Pré-moldado',
                                File.join('detalhamento_pm', 'main'))
    ext.description = 'Gera pranchas A3 de formas em PDF (e DXF opcional) de cada peça pré-moldada: ' \
                      'vistas superior e lateral com linhas ocultas, cortes ' \
                      'automáticos, modelo 3D, resumo, revisões e carimbo.'
    ext.version     = '0.3.0'
    ext.creator     = 'MarcoAntonioMartins'
    ext.copyright   = '2026 MarcoAntonioMartins'
    Sketchup.register_extension(ext, true)
    file_loaded(__FILE__)
  end
end
