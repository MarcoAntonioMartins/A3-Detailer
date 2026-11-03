# encoding: UTF-8
# Detalhamento Pré-moldado - integração com o SketchUp.
# Lê as peças do modelo, agrupa as iguais e gera uma prancha A3 de formas
# (DXF) para cada tipo de peça.
require 'sketchup.rb'

dir = File.dirname(__FILE__)
require File.join(dir, 'geom')
require File.join(dir, 'dxf')
require File.join(dir, 'prancha')

module DetalhamentoPM
  module Core
    PREF = 'DetalhamentoPM'.freeze

    CAMPOS = [
      # chave, rótulo, padrão
      ['tags',     'Tags a detalhar (separe com vírgula; vazio = todas)',
       'Bloco,Pilares,Consoles,Placas,Vigas,Lajes,Tesouras'],
      ['insertos', 'Palavras que identificam insertos',
       'insert,neoprene,alça,alca,chapa,içamento,icamento'],
      ['obra',     'Obra', 'EDIFICAÇÃO COMERCIAL'],
      ['local',    'Local', '-'],
      ['prefixo',  'Prefixo do arquivo', 'EC'],
      ['codigo',   'Código da obra no nome do arquivo', 'OBRA'],
      ['revisao',  'Revisão atual', '00'],
      ['revisoes', 'Histórico de revisões (separe com ;)', '00 - EMISSÃO INICIAL'],
      ['data',     'Data (vazio = hoje)', ''],
      ['fck',      'Fck (MPa)', '40'],
      ['peso_esp', 'Peso específico do concreto (t/m³)', '2,5'],
      ['fonte',    'Fonte do texto no DXF', 'romans.shx']
    ].freeze

    TIPOS = [
      ['pilar', 'PILAR', 'PILARES'], ['viga', 'VIGA', 'VIGAS'],
      ['placa', 'PLACA', 'PLACAS'], ['laje', 'LAJE', 'LAJES'],
      ['tesoura', 'TESOURA', 'TESOURAS'], ['bloco', 'BLOCO', 'BLOCOS'],
      ['console', 'CONSOLE', 'CONSOLES'], ['terça', 'TERÇA', 'TERÇAS'],
      ['terca', 'TERÇA', 'TERÇAS']
    ].freeze

    # ------------------------------------------------------------ config
    def self.valores
      h = {}
      CAMPOS.each { |k, _, pad| h[k] = Sketchup.read_default(PREF, k, pad).to_s }
      h
    end

    def self.configurar(titulo)
      v = valores
      r = UI.inputbox(CAMPOS.map { |c| c[1] }, CAMPOS.map { |c| v[c[0]] }, titulo)
      return nil unless r
      CAMPOS.each_with_index { |c, i| Sketchup.write_default(PREF, c[0], r[i].to_s) }
      cfg_prancha
    end

    def self.cfg_prancha
      v = valores
      {
        tags: v['tags'].split(',').map { |s| s.strip.downcase }.reject(&:empty?),
        insertos: v['insertos'].split(',').map { |s| s.strip.downcase }.reject(&:empty?),
        obra: v['obra'], local: v['local'], prefixo: v['prefixo'],
        codigo: v['codigo'], revisao: v['revisao'],
        revisoes: v['revisoes'].split(';').map(&:strip).reject(&:empty?),
        data: v['data'].strip.empty? ? Time.now.strftime('%d/%m/%Y') : v['data'],
        fck: v['fck'], peso_esp: v['peso_esp'].tr(',', '.').to_f,
        fonte: v['fonte'].strip.empty? ? 'romans.shx' : v['fonte'].strip
      }
    end

    # ------------------------------------------------------------ coleta
    def self.instancias(ents)
      ents.grep(Sketchup::ComponentInstance) + ents.grep(Sketchup::Group)
    end

    def self.tag_ok?(inst, filt)
      return true if filt.empty?
      nome = inst.layer.name.downcase
      filt.any? { |f| nome.include?(f) }
    end

    def self.coletar(ents, filt, out = [])
      instancias(ents).each do |i|
        next if i.hidden? || !i.layer.visible?
        if tag_ok?(i, filt)
          out << i
        else
          coletar(i.definition.entities, filt, out)
        end
      end
      out
    end

    def self.nome_peca(i)
      n = i.name.to_s.strip
      n = i.definition.name.to_s if n.empty?
      n.sub(/#\d+\z/, '').strip
    end

    def self.inserto?(i, palavras)
      txt = [i.layer.name, i.name, i.definition.name].join(' ').downcase
      palavras.any? { |p| txt.include?(p) }
    end

    def self.tipo(tag, nome)
      t = "#{tag} #{nome}".downcase
      achado = TIPOS.find { |k, _, _| t.include?(k) }
      achado ? [achado[1], achado[2]] : ['PEÇA', 'PEÇAS']
    end

    def self.escala(i)
      t = i.transformation
      [Geom::Vector3d.new(1, 0, 0), Geom::Vector3d.new(0, 1, 0),
       Geom::Vector3d.new(0, 0, 1)].map { |v| v.transform(t).length.to_f }
    end

    def self.mm(p)
      [p.x.to_f * 25.4, p.y.to_f * 25.4, p.z.to_f * 25.4]
    end

    # Percorre a peça: faces e arestas de concreto vão para d[:tris] e
    # d[:arestas]; o que for inserto vai para d[:insertos] (só arestas).
    def self.extrair(ents, tr, d, palavras, ins = nil)
      ents.each do |e|
        if e.is_a?(Sketchup::Face)
          next if ins || e.hidden?
          m = e.mesh(0)
          pts = (1..m.count_points).map { |k| mm(m.point_at(k).transform(tr)) }
          m.polygons.each do |pol|
            idx = pol.map(&:abs)
            d[:tris] << idx.map { |k| pts[k - 1] } if idx.size == 3
          end
        elsif e.is_a?(Sketchup::Edge)
          next if e.hidden? || e.soft?
          seg = [mm(e.start.position.transform(tr)), mm(e.end.position.transform(tr))]
          (ins ? ins[:arestas] : d[:arestas]) << seg
        elsif e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group)
          next if e.hidden? || !e.layer.visible?
          t2 = tr * e.transformation
          if ins.nil? && inserto?(e, palavras)
            novo = { nome: nome_peca(e), arestas: [] }
            d[:insertos] << novo
            extrair(e.definition.entities, t2, d, palavras, novo)
          else
            extrair(e.definition.entities, t2, d, palavras, ins)
          end
        end
      end
      d
    end

    def self.volume_m3(i)
      v = i.volume
      v > 0 ? v * (0.0254**3) : nil
    rescue StandardError
      nil
    end

    # Agrupa peças iguais (mesmo nome e mesmas dimensões).
    def self.agrupar(pecas, cfg)
      cache = {}
      tipos = {}
      pecas.each do |i|
        esc = escala(i)
        ck  = [i.definition, esc.map { |s| s.round(4) }]
        cache[ck] ||= extrair(i.definition.entities,
                              Geom::Transformation.scaling(*esc),
                              { tris: [], arestas: [], insertos: [] }, cfg[:insertos])
        geo = cache[ck]
        pts = geo[:tris].flatten(1) + geo[:arestas].flatten(1)
        next if pts.empty?
        dims = (0..2).map { |k| pts.map { |q| q[k] }.max - pts.map { |q| q[k] }.min }.sort
        nome = nome_peca(i)
        chave = [nome] + dims.map(&:round)
        t = tipos[chave]
        unless t
          tp, tpl = tipo(i.layer.name, nome)
          t = tipos[chave] = {
            nome: nome, tag: i.layer.name, tipo: tp, tipo_plural: tpl, qtd: 0,
            tris: geo[:tris], arestas: geo[:arestas], insertos: geo[:insertos],
            volume_m3: volume_m3(i), dims: dims
          }
        end
        t[:qtd] += 1
      end
      tipos.values.sort_by { |t| [t[:tag], t[:nome]] }
    end

    def self.pecas_do_modelo(selecao, cfg)
      model = Sketchup.active_model
      if selecao
        instancias(model.selection.to_a)
      else
        coletar(model.entities, cfg[:tags])
      end
    end

    # ------------------------------------------------------------ comandos
    def self.gerar_pranchas(selecao = false)
      model = Sketchup.active_model
      if selecao && instancias(model.selection.to_a).empty?
        UI.messagebox('Selecione uma ou mais peças (componentes ou grupos).')
        return
      end
      cfg = configurar('Pranchas A3 de formas')
      return unless cfg
      pecas = pecas_do_modelo(selecao, cfg)
      if pecas.empty?
        UI.messagebox('Nenhuma peça encontrada. Confira o filtro de tags ' \
                      'ou se as peças são componentes/grupos.')
        return
      end
      pasta = UI.select_directory(title: 'Pasta onde salvar as pranchas (DXF)')
      return unless pasta

      Sketchup.status_text = 'Lendo as peças...'
      tipos = agrupar(pecas, cfg)
      feitas = []
      erros = []
      tipos.each_with_index do |t, k|
        Sketchup.status_text = "Gerando prancha #{k + 1}/#{tipos.size}: #{t[:nome]}"
        begin
          pr = Prancha.new(t, cfg)
          caminho = File.join(pasta, pr.nome_arquivo + '.dxf')
          pr.gerar(caminho)
          feitas << "#{File.basename(caminho)}  (vistas 1:#{pr.escala_vistas})"
        rescue StandardError => e
          erros << "#{t[:nome]}: #{e.message}"
          puts "[Detalhamento PM] #{t[:nome]}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        end
      end
      Sketchup.status_text = ''

      msg = "#{feitas.size} prancha(s) gerada(s) em:\n#{pasta}\n\n"
      msg += feitas.first(15).join("\n")
      msg += "\n..." if feitas.size > 15
      msg += "\n\nNão foi possível gerar:\n#{erros.join("\n")}" unless erros.empty?
      msg += "\n\nAbrir a pasta?"
      if UI.messagebox(msg, MB_YESNO) == IDYES
        UI.openURL('file:///' + pasta.tr('\\', '/'))
      end
    end

    def self.exportar_csv
      cfg = configurar('Lista de peças')
      return unless cfg
      tipos = agrupar(pecas_do_modelo(false, cfg), cfg)
      if tipos.empty?
        UI.messagebox('Nenhuma peça encontrada com o filtro de tags atual.')
        return
      end
      path = UI.savepanel('Salvar lista de peças', '', 'lista_de_pecas.csv')
      return unless path
      path += '.csv' unless path.downcase.end_with?('.csv')
      fmt = lambda { |v, c| v.nil? ? '' : format("%.#{c}f", v).tr('.', ',') }
      linhas = [['Peça', 'Tipo', 'Tag', 'Qtd', 'Largura (cm)', 'Altura (cm)',
                 'Comp. (cm)', 'Volume unit. (m³)', 'Volume total (m³)', 'Peso unit. (t)']]
      tipos.each do |t|
        a, b, l = t[:dims].map { |v| v / 10.0 }
        vol = t[:volume_m3] || G.volume(t[:tris]) / 1e9
        linhas << [t[:nome], t[:tipo], t[:tag], t[:qtd], fmt.call(a, 1), fmt.call(b, 1),
                   fmt.call(l, 1), fmt.call(vol, 3), fmt.call(vol * t[:qtd], 3),
                   fmt.call(vol * cfg[:peso_esp], 2)]
      end
      File.open(path, 'w:UTF-8') do |f|
        f.write("﻿")
        linhas.each { |ln| f.puts(ln.map { |v| "\"#{v.to_s.gsub('"', '""')}\"" }.join(';')) }
      end
      UI.messagebox("Lista salva em:\n#{path}")
    rescue StandardError => e
      UI.messagebox("Erro ao exportar:\n#{e.message}")
    end

    # ------------------------------------------------------------ menus
    unless file_loaded?(__FILE__)
      m = UI.menu('Extensions').add_submenu('Detalhamento Pré-moldado')
      m.add_item('Gerar pranchas A3 (todas as peças)...') { gerar_pranchas(false) }
      m.add_item('Gerar prancha das peças selecionadas...') { gerar_pranchas(true) }
      m.add_separator
      m.add_item('Exportar lista de peças (CSV)...') { exportar_csv }

      UI.add_context_menu_handler do |menu|
        sel = Sketchup.active_model.selection
        if sel.any? { |e| e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group) }
          menu.add_item('Gerar prancha A3 da peça') { gerar_pranchas(true) }
        end
      end
      file_loaded(__FILE__)
    end
  end
end
