# encoding: UTF-8
# Gravador PDF vetorial mínimo (Ruby puro): linhas e textos em folha A3
# deitada. Coordenadas de entrada em mm de papel (mesmas do DXF).
# Suporta várias páginas (uma prancha por página).
module DetalhamentoPM
  class PDF
    PT = 72.0 / 25.4
    LARG = 420.0
    ALT  = 297.0

    # camada => [cor RGB 0..1, espessura mm, traço (mm) ou nil]
    ESTILOS = {
      'FOLHA'    => [[0, 0, 0], 0.50, nil],
      'CARIMBO'  => [[0, 0, 0], 0.25, nil],
      'CONTORNO' => [[0, 0, 0], 0.40, nil],
      'OCULTO'   => [[0, 0, 0], 0.18, [1.5, 0.75]],
      'COTAS'    => [[0, 0, 0], 0.13, nil],
      'TEXTO'    => [[0, 0, 0], 0.18, nil],
      'HACHURA'  => [[0.55, 0.55, 0.55], 0.10, nil],
      'INSERTOS' => [[0.85, 0, 0.85], 0.25, nil],
      'CORTE'    => [[0.85, 0, 0], 0.30, nil],
      'MODELO3D' => [[0, 0, 0], 0.18, nil]
    }.freeze

    LARGURAS = [278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333,
                278, 278, 556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278,
                584, 584, 584, 556, 1015, 667, 667, 722, 722, 667, 611, 778, 722, 278,
                500, 667, 556, 833, 722, 778, 667, 778, 722, 667, 611, 722, 667, 944,
                667, 667, 611, 278, 278, 278, 469, 556, 333, 556, 556, 500, 556, 556,
                278, 556, 556, 222, 222, 500, 222, 833, 556, 556, 556, 556, 333, 500,
                278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584].freeze
    ESCALA_H = 0.8   # mesma largura de letra do estilo do DXF

    def initialize
      @paginas = []
    end

    def nova_pagina
      @atual = Hash.new { |h, k| h[k] = +'' }
      @textos = String.new(encoding: Encoding::BINARY)
      @paginas << [@atual, @textos]
    end

    def n(v)
      format('%.3f', v.to_f * PT).sub(/\.?0+\z/, '')
    end

    def line(x1, y1, x2, y2, camada)
      nova_pagina unless @atual
      @atual[camada] << "#{n(x1)} #{n(y1)} m #{n(x2)} #{n(y2)} l\n"
    end

    def largura_texto(s, tam_pt)
      s.to_s.each_char.inject(0.0) do |soma, ch|
        base = ch.unicode_normalize(:nfd)[0] rescue ch
        o = base.ord
        w = o >= 32 && o <= 126 ? LARGURAS[o - 32] : (ch == '³' ? 333 : 556)
        soma + w
      end * tam_pt / 1000.0 * ESCALA_H
    end

    def esc(s)
      b = s.to_s.encode('Windows-1252', invalid: :replace, undef: :replace, replace: '?')
      b.force_encoding('BINARY').gsub(/[\\()]/n) { |c| "\\#{c}" }
    end

    # h = altura de maiúscula em mm (como no DXF)
    def text(s, x, y, h, camada, alinh = 0, rot = 0)
      nova_pagina unless @atual
      tam = h * PT / 0.718
      w = largura_texto(s, tam)
      a = rot * Math::PI / 180.0
      c = Math.cos(a)
      sn = Math.sin(a)
      desl = alinh == 1 ? w / 2.0 : (alinh == 2 ? w : 0.0)
      px = x * PT - desl * c
      py = y * PT - desl * sn
      cor = (ESTILOS[camada] || ESTILOS['TEXTO'])[0]
      @textos << "BT /F1 #{format('%.2f', tam)} Tf #{(ESCALA_H * 100).round} Tz " \
                 "#{cor.join(' ')} rg #{format('%.5f %.5f %.5f %.5f %.3f %.3f', c, sn, -sn, c, px, py)} Tm ("
      @textos << esc(s)
      @textos << ") Tj ET\n"
    end

    def conteudo_pagina(linhas, textos)
      o = +"1 J 1 j\n"
      ESTILOS.each do |camada, (cor, esp, traco)|
        next if linhas[camada].empty?
        o << "#{cor.join(' ')} RG #{n(esp)} w "
        o << (traco ? "[#{traco.map { |t| n(t) }.join(' ')}] 0 d\n" : "[] 0 d\n")
        o << linhas[camada] << "S\n"
      end
      (linhas.keys - ESTILOS.keys).each { |k| o << "0 0 0 RG [] 0 d " << linhas[k] << "S\n" }
      o.force_encoding('BINARY') << textos.force_encoding('BINARY')
    end

    def salvar(caminho)
      nova_pagina if @paginas.empty?
      objs = []
      kids = []
      fonte = 3
      objs[1] = '<< /Type /Catalog /Pages 2 0 R >>'
      objs[3] = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>'
      prox = 4
      @paginas.each do |linhas, textos|
        cont = conteudo_pagina(linhas, textos)
        pid = prox
        cid = prox + 1
        prox += 2
        kids << pid
        objs[pid] = "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 #{n(LARG)} #{n(ALT)}] " \
                    "/Resources << /Font << /F1 #{fonte} 0 R >> >> /Contents #{cid} 0 R >>"
        objs[cid] = "<< /Length #{cont.bytesize} >>\nstream\n".b + cont + "\nendstream".b
      end
      objs[2] = "<< /Type /Pages /Kids [#{kids.map { |k| "#{k} 0 R" }.join(' ')}] /Count #{kids.size} >>"

      out = "%PDF-1.4\n%\xE2\xE3\xCF\xD3\n".b
      offs = []
      (1...objs.size).each do |i|
        offs[i] = out.bytesize
        out << "#{i} 0 obj\n".b << objs[i].to_s.b << "\nendobj\n".b
      end
      xref = out.bytesize
      out << "xref\n0 #{objs.size}\n0000000000 65535 f \n".b
      (1...objs.size).each { |i| out << format("%010d 00000 n \n", offs[i]).b }
      out << "trailer\n<< /Size #{objs.size} /Root 1 0 R >>\nstartxref\n#{xref}\n%%EOF\n".b
      File.open(caminho, 'wb') { |f| f.write(out) }
      caminho
    end
  end

  # Envia o mesmo desenho para vários gravadores (PDF e/ou DXF).
  class Saidas
    def initialize(lista)
      @lista = lista
    end

    def line(*a)
      @lista.each { |s| s.line(*a) }
    end

    def text(*a)
      @lista.each { |s| s.text(*a) }
    end
  end
end
