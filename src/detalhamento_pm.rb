# encoding: UTF-8
# Detalhamento Pré-moldado - carregador da extensão
require 'sketchup.rb'
require 'extensions.rb'

module DetalhamentoPM
  unless file_loaded?(__FILE__)
    ext = SketchupExtension.new('Detalhamento Pré-moldado',
                                File.join('detalhamento_pm', 'main'))
    ext.description = 'Gera vistas 2D cotadas (superior, frontal e lateral) ' \
                      'de cada peça do modelo e exporta a lista de peças em CSV.'
    ext.version     = '0.1.0'
    ext.creator     = 'MarcoAntonioMartins'
    ext.copyright   = '2026 MarcoAntonioMartins'
    Sketchup.register_extension(ext, true)
    file_loaded(__FILE__)
  end
end
