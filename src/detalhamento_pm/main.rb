# encoding: UTF-8
# Detalhamento Pré-moldado
# Lê as peças do modelo (componentes e grupos), agrupa as iguais e desenha
# vistas 2D cotadas de cada uma ao lado do modelo.
require 'sketchup.rb'

module DetalhamentoPM
  module Core
    PREF        = 'DetalhamentoPM'.freeze
    NOME_GRUPO  = 'Detalhamento 2D'.freeze
    TAGS_PADRAO = 'Bloco,Pilares,Consoles,Placas,Vigas,Lajes,Tesouras'.freeze
    TOL         = 0.5.cm   # cotas parciais mais próximas que isso são unidas
    MAX_PARCIAIS = 20      # acima disso, mostra só a cota total

    VISTAS = [
      ['VISTA SUPERIOR', lambda { |p| [p.x, p.y] }],
      ['VISTA FRONTAL',  lambda { |p| [p.x, p.z] }],
      ['VISTA LATERAL',  lambda { |p| [p.y, p.z] }]
    ].freeze

    # ---------------------------------------------------------------- config
    def self.cfg
      {
        tags:     Sketchup.read_default(PREF, 'tags', TAGS_PADRAO).to_s,
        parciais: Sketchup.read_default(PREF, 'parciais', 'Sim').to_s,
        espaco:   Sketchup.read_default(PREF, 'espaco', 60).to_f,
        texto:    Sketchup.read_default(PREF, 'texto', 10).to_f
      }
    end

    def self.configurar
      c = cfg
      prompts  = ['Tags a detalhar (separadas por vírgula; vazio = todas)',
                  'Cotas parciais (consoles, recortes etc.)',
                  'Espaço entre vistas (cm)',
                  'Altura do texto (cm)']
      defaults = [c[:tags], c[:parciais], c[:espaco].to_s, c[:texto].to_s]
      listas   = ['', 'Sim|Não', '', '']
      r = UI.inputbox(prompts, defaults, listas, 'Detalhamento Pré-moldado')
      return false unless r
      Sketchup.write_default(PREF, 'tags', r[0].to_s)
      Sketchup.write_default(PREF, 'parciais', r[1].to_s)
      Sketchup.write_default(PREF, 'espaco', r[2].to_s.tr(',', '.').to_f)
      Sketchup.write_default(PREF, 'texto', r[3].to_s.tr(',', '.').to_f)
      true
    end

    def self.filtros
      cfg[:tags].split(',').map { |s| s.strip.downcase }.reject(&:empty?)
    end

    # ------------------------------------------------------------- coleta
    def self.instancias(ents)
      ents.grep(Sketchup::ComponentInstance) + ents.grep(Sketchup::Group)
    end

    def self.tag_ok?(inst, filt)
      return true if filt.empty?
      nome = inst.layer.name.downcase
      filt.any? { |f| nome.include?(f) }
    end

    # Desce pela hierarquia até achar instâncias cuja tag bate com o filtro.
    # O que estiver dentro de uma peça encontrada (consoles, insertos...)
    # passa a fazer parte do desenho dessa peça.
    def self.coletar(ents, filt, out = [])
      instancias(ents).each do |i|
        next if i.name.start_with?(NOME_GRUPO)
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
      n.empty? ? i.definition.name : n
    end

    # Escala própria da instância (componentes esticados), sem rotação.
    def self.escala(i)
      t = i.transformation
      [Geom::Vector3d.new(1, 0, 0), Geom::Vector3d.new(0, 1, 0),
       Geom::Vector3d.new(0, 0, 1)].map { |v| v.transform(t).length.to_f }
    end

    def self.arestas(ents, tr, out = [])
      ents.each do |e|
        if e.is_a?(Sketchup::Edge)
          next if e.hidden? || e.soft?
          out << [e.start.position.transform(tr), e.end.position.transform(tr)]
        elsif e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group)
          next if e.hidden?
          arestas(e.definition.entities, tr * e.transformation, out)
        end
      end
      out
    end

    # Move a peça para começar em (0,0,0) e devolve [segmentos, [x, y, z]].
    def self.normalizar(segs)
      return [[], [0, 0, 0]] if segs.empty?
      pts = segs.flatten
      mn = [pts.map(&:x).min, pts.map(&:y).min, pts.map(&:z).min]
      mx = [pts.map(&:x).max, pts.map(&:y).max, pts.map(&:z).max]
      v = Geom::Vector3d.new(-mn[0], -mn[1], -mn[2])
      [segs.map { |a, b| [a.offset(v), b.offset(v)] },
       [mx[0] - mn[0], mx[1] - mn[1], mx[2] - mn[2]]]
    end

    def self.volume_m3(i)
      v = i.volume
      v > 0 ? v * (0.0254**3) : nil
    rescue StandardError
      nil
    end

    # Agrupa peças iguais (mesmo nome e mesmas dimensões).
    def self.agrupar(pecas)
      cache = {}
      tipos = {}
      pecas.each do |i|
        esc = escala(i)
        ck  = [i.definition, esc.map { |s| s.round(4) }]
        cache[ck] ||= normalizar(arestas(i.definition.entities,
                                         Geom::Transformation.scaling(*esc)))
        segs, dims = cache[ck]
        next if segs.empty?
        nome  = nome_peca(i)
        chave = [nome] + dims.map { |d| d.to_mm.round }
        t = (tipos[chave] ||= { nome: nome, tag: i.layer.name, segs: segs,
                                dims: dims, qtd: 0, volume: volume_m3(i) })
        t[:qtd] += 1
      end
      tipos.values.sort_by { |t| [t[:tag], t[:nome]] }
    end

    # ------------------------------------------------------------- desenho
    def self.texto(ents, str, pos, altura)
      g = ents.add_group
      g.entities.add_3d_text(str, TextAlignLeft, 'Arial', false, false,
                             altura, 0.0, 0.0, true, 0.0)
      g.transform!(Geom::Transformation.translation(pos))
      g
    end

    def self.quebras(vals, total)
      vs  = vals.select { |x| x > TOL && x < total - TOL }.uniq.sort
      res = [0.0]
      vs.each { |x| res << x if x - res.last > TOL }
      res << total
      res
    end

    def self.cotar(ge, w, h, us, vs, d, parciais)
      if w > TOL
        q = quebras(us, w)
        if parciais && q.size > 2 && q.size <= MAX_PARCIAIS + 1
          q.each_cons(2) do |a, b|
            ge.add_dimension_linear([a, 0, 0], [b, 0, 0], [0, -d, 0])
          end
          ge.add_dimension_linear([0, 0, 0], [w, 0, 0], [0, -2 * d, 0])
        else
          ge.add_dimension_linear([0, 0, 0], [w, 0, 0], [0, -d, 0])
        end
      end
      return unless h > TOL
      q = quebras(vs, h)
      if parciais && q.size > 2 && q.size <= MAX_PARCIAIS + 1
        q.each_cons(2) do |a, b|
          ge.add_dimension_linear([0, a, 0], [0, b, 0], [-d, 0, 0])
        end
        ge.add_dimension_linear([0, 0, 0], [0, h, 0], [-2 * d, 0, 0])
      else
        ge.add_dimension_linear([0, 0, 0], [0, h, 0], [-d, 0, 0])
      end
    end

    def self.desenhar_vista(pai, segs, map, titulo, origem, d, c)
      g  = pai.entities.add_group
      g.name = titulo
      ge = g.entities
      vistos = {}
      us = []
      vs = []
      segs.each do |a, b|
        ua, va = map.call(a)
        ub, vb = map.call(b)
        ka = [ua.to_mm.round(1), va.to_mm.round(1)]
        kb = [ub.to_mm.round(1), vb.to_mm.round(1)]
        next if ka == kb
        k = [ka, kb].sort
        next if vistos[k]
        vistos[k] = true
        ge.add_line([ua, va, 0], [ub, vb, 0])
        us << ua << ub
        vs << va << vb
      end
      w = us.max.to_f
      h = vs.max.to_f
      cotar(ge, w, h, us, vs, d, c[:parciais] == 'Sim')
      texto(ge, titulo, [0, h + d * 0.6, 0], c[:texto].cm * 0.7)
      g.transform!(Geom::Transformation.translation(origem))
      [w, h]
    end

    def self.fmt(v, casas = 1)
      format("%.#{casas}f", v).tr('.', ',')
    end

    def self.desenhar_peca(folha, t, x0, y_topo, c)
      x, y, z = t[:dims]
      d = [[[x, y, z].max * 0.05, 12.cm].max, 40.cm].min
      txt = c[:texto].cm
      esp = c[:espaco].cm

      tamanhos = [[x, y], [x, z], [y, z]]
      hmax = tamanhos.map { |_, h| h }.max
      base_y = y_topo - txt * 2.5 - d - hmax

      cab = "#{t[:nome]}   |   QTD: #{t[:qtd]}   |   #{t[:tag]}   |   " \
            "#{fmt(x.to_cm)} x #{fmt(y.to_cm)} x #{fmt(z.to_cm)} cm"
      cab += "   |   #{fmt(t[:volume], 3)} m³" if t[:volume]
      texto(folha.entities, cab, [x0, y_topo - txt, 0], txt)

      cx = x0 + 2.5 * d
      VISTAS.each_with_index do |(titulo, map), k|
        w, = tamanhos[k]
        desenhar_vista(folha, t[:segs], map, titulo, [cx, base_y, 0], d, c)
        cx += w + 3.5 * d + esp
      end
      base_y - 2.5 * d - esp * 1.5
    end

    def self.apagar_existente(model)
      grupos = model.entities.grep(Sketchup::Group)
                    .select { |g| g.name.start_with?(NOME_GRUPO) }
      model.entities.erase_entities(grupos) unless grupos.empty?
      grupos.size
    end

    # ------------------------------------------------------------- comandos
    def self.gerar(somente_selecao = false)
      model = Sketchup.active_model
      if somente_selecao
        pecas = instancias(model.selection.to_a)
                .reject { |i| i.name.start_with?(NOME_GRUPO) }
      else
        return unless configurar
        pecas = coletar(model.entities, filtros)
      end
      if pecas.empty?
        UI.messagebox('Nenhuma peça encontrada. Confira o filtro de tags ' \
                      'ou se as peças são componentes/grupos.')
        return
      end

      substituir = false
      unless somente_selecao
        existe = model.entities.grep(Sketchup::Group)
                      .any? { |g| g.name.start_with?(NOME_GRUPO) }
        if existe
          r = UI.messagebox('Já existe um detalhamento no modelo. Substituir?',
                            MB_YESNOCANCEL)
          return if r == IDCANCEL
          substituir = (r == IDYES)
        end
      end

      c = cfg
      model.start_operation('Gerar detalhamento 2D', true)
      begin
        apagar_existente(model) if substituir
        tipos = agrupar(pecas)
        tag = model.layers['Detalhamento 2D'] || model.layers.add('Detalhamento 2D')
        folha = model.entities.add_group
        folha.name  = somente_selecao ? "#{NOME_GRUPO} - seleção" : NOME_GRUPO
        folha.layer = tag

        bb = model.bounds
        x0 = bb.max.x + 5.m
        y  = bb.max.y
        tipos.each { |t| y = desenhar_peca(folha, t, x0, y, c) }

        model.commit_operation
        total = tipos.inject(0) { |s, t| s + t[:qtd] }
        UI.messagebox("Detalhamento gerado: #{tipos.size} tipo(s) de peça, " \
                      "#{total} peça(s) no total.\n\nUse Câmera > Projeção " \
                      "paralela e a vista Topo para visualizar.")
        Sketchup.active_model.active_view.zoom(folha)
      rescue StandardError => e
        model.abort_operation
        UI.messagebox("Erro ao gerar o detalhamento:\n#{e.message}")
        puts e.backtrace.join("\n")
      end
    end

    def self.exportar_csv
      model = Sketchup.active_model
      return unless configurar
      tipos = agrupar(coletar(model.entities, filtros))
      if tipos.empty?
        UI.messagebox('Nenhuma peça encontrada com o filtro de tags atual.')
        return
      end
      path = UI.savepanel('Salvar lista de peças', '', 'lista_de_pecas.csv')
      return unless path
      path += '.csv' unless path.downcase.end_with?('.csv')

      linhas = [['Peça', 'Tag', 'Qtd', 'X (cm)', 'Y (cm)', 'Z (cm)',
                 'Volume unit. (m³)', 'Volume total (m³)']]
      tipos.each do |t|
        x, y, z = t[:dims].map(&:to_cm)
        vu = t[:volume]
        linhas << [t[:nome], t[:tag], t[:qtd], fmt(x), fmt(y), fmt(z),
                   vu ? fmt(vu, 3) : '', vu ? fmt(vu * t[:qtd], 3) : '']
      end
      File.open(path, 'w:UTF-8') do |f|
        f.write("﻿")
        linhas.each do |l|
          f.puts(l.map { |v| "\"#{v.to_s.gsub('"', '""')}\"" }.join(';'))
        end
      end
      UI.messagebox("Lista salva em:\n#{path}")
    rescue StandardError => e
      UI.messagebox("Erro ao exportar:\n#{e.message}")
    end

    def self.apagar_interativo
      model = Sketchup.active_model
      return unless UI.messagebox('Apagar todo o detalhamento 2D gerado?',
                                  MB_YESNO) == IDYES
      model.start_operation('Apagar detalhamento 2D', true)
      n = apagar_existente(model)
      model.commit_operation
      UI.messagebox("#{n} grupo(s) de detalhamento apagado(s).")
    end

    # ------------------------------------------------------------- menus
    unless file_loaded?(__FILE__)
      m = UI.menu('Extensions').add_submenu('Detalhamento Pré-moldado')
      m.add_item('Gerar detalhamento 2D...')          { gerar(false) }
      m.add_item('Detalhar peças selecionadas')       { gerar(true) }
      m.add_separator
      m.add_item('Exportar lista de peças (CSV)...')  { exportar_csv }
      m.add_item('Apagar detalhamento 2D')            { apagar_interativo }

      UI.add_context_menu_handler do |menu|
        sel = Sketchup.active_model.selection
        if sel.any? { |e| e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group) }
          menu.add_item('Detalhar peça(s) selecionada(s)') { gerar(true) }
        end
      end
      file_loaded(__FILE__)
    end
  end
end
