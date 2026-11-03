# encoding: UTF-8
# Monta uma prancha A3 de formas para uma peça (Ruby puro).
#
# peca = {
#   nome: 'PPF1', tag: '2. Pilares', tipo: 'PILAR', tipo_plural: 'PILARES',
#   qtd: 11, tris: [[p, p, p], ...], arestas: [[p, p], ...],
#   insertos: [{ nome: 'ALÇA DE IÇAMENTO', arestas: [[p, p], ...] }],
#   volume_m3: 1.12 (opcional)
# }   (pontos em mm)
#
# cfg = { obra:, local:, prefixo:, codigo:, revisao:, revisoes: [...],
#         data:, fck:, peso_esp:, fonte: }
module DetalhamentoPM
  class Prancha
    ESCALAS = [5, 10, 15, 20, 25, 30, 40, 50, 75, 100, 125, 150, 200, 250,
               300, 400, 500].freeze
    ROW = 6.0          # distância entre linhas de cota (mm de papel)
    TD  = 2.0          # altura do texto das cotas
    FX0 = 25.0         # moldura (NBR 16752: margem esquerda 25, demais 7)
    FY0 = 7.0
    FX1 = 413.0
    FY1 = 290.0
    CW  = 190.0        # largura do bloco carimbo/tabelas
    MAX_CADEIA = 25
    TOL = 5.0          # mm reais: pontos de cota mais próximos que isso se unem

    attr_reader :escala_vistas, :escala_cortes, :cortes

    def initialize(peca, cfg)
      @p = peca
      @c = cfg
      preparar
    end

    def nome_arquivo
      partes = [@c[:prefixo], @c[:codigo], 'DET', @p[:nome], "R#{@c[:revisao]}"]
      partes.map { |s| s.to_s.strip }.reject(&:empty?).join('-')
            .gsub(%r{[\\/:*?"<>|]}, '_')
    end

    # Atalho: grava a prancha num arquivo .dxf ou .pdf.
    def gerar(caminho)
      if caminho.downcase.end_with?('.pdf')
        g = PDF.new
        g.nova_pagina
      else
        g = DXF.new(@c[:fonte] || 'romans.shx')
      end
      desenhar(g)
      g.salvar(caminho)
    end

    # Desenha a prancha num gravador (DXF, página de PDF ou Saidas).
    def desenhar(saida)
      @d = saida
      folha
      y_dir = carimbo_e_tabelas
      @cortes = calcular_cortes
      iso = calcular_iso

      col = [FX1 - 33, FX1 - 3, y_dir + 4, FY1 - 4]
      blx = [FX1 - CW - 70, FX1 - CW - 4, FY0 + 4, y_dir - 2]
      k_col = fator(iso, col)
      k_blx = fator(iso, blx)
      na_coluna = k_col >= k_blx
      if na_coluna
        desenhar_iso(iso, col, k_col)
        vx1 = col[0] - 4
        cx1 = FX1 - CW - 4
      else
        desenhar_iso(iso, blx, k_blx)
        vx1 = FX1 - 3
        cx1 = blx[0] - 3
      end
      vistas(FX0 + 17, vx1, y_dir + 3, FY1 - 2)
      desenhar_cortes(FX0 + 3, cx1, FY0 + 3, y_dir - 1)
      self
    end

    # ------------------------------------------------------------ preparo
    def preparar
      pts = @p[:tris].flatten(1) + @p[:arestas].flatten(1)
      raise 'Peça sem geometria de concreto' if pts.empty?
      mn = (0..2).map { |i| pts.map { |q| q[i] }.min }
      mx = (0..2).map { |i| pts.map { |q| q[i] }.max }
      mv = lambda { |q| G.sub(q, mn) }
      @tris    = @p[:tris].map { |t| t.map(&mv) }
      @arestas = @p[:arestas].map { |s| s.map(&mv) }
      @insertos = (@p[:insertos] || []).map do |i|
        { nome: i[:nome].to_s, arestas: i[:arestas].map { |s| s.map(&mv) } }
      end
      @insertos.reject! { |i| i[:arestas].empty? }
      @dim = (0..2).map { |i| mx[i] - mn[i] }
      @ia, @ib, @il = [0, 1, 2].sort_by { |i| [@dim[i], -i] }
      @A = @dim[@ia]
      @B = @dim[@ib]
      @L = @dim[@il]
      e = lambda { |i| v = [0.0, 0.0, 0.0]; v[i] = 1.0; v }
      @vl = G::Vista.new(e.call(@il), e.call(@ib))   # vista lateral
      @vs = G::Vista.new(e.call(@il), e.call(@ia))   # vista superior
      @vi = G::Vista.new([1.0, -1.0, 0.0], [1.0, 1.0, 2.0]) # isométrica
      @verts = @tris.flatten(1) + @arestas.flatten(1)
      @vol = @p[:volume_m3] || G.volume(@tris) / 1e9
    end

    # ------------------------------------------------------------ primitivas
    def l(x1, y1, x2, y2, camada = 'CARIMBO')
      @d.line(x1, y1, x2, y2, camada)
    end

    def rect(x0, y0, x1, y1, camada = 'CARIMBO')
      l(x0, y0, x1, y0, camada)
      l(x1, y0, x1, y1, camada)
      l(x1, y1, x0, y1, camada)
      l(x0, y1, x0, y0, camada)
    end

    def txt(s, x, y, h, camada = 'TEXTO', alinh = 0, rot = 0)
      @d.text(s, x, y, h, camada, alinh, rot)
    end

    def larg(s, h)
      s.to_s.length * h * 0.72
    end

    def fmt_cm(mm)
      v = (mm / 10.0).round(1)
      s = v == v.round ? v.round.to_s : format('%.1f', v)
      s.tr('.', ',')
    end

    def fmt2(v)
      format('%.2f', v).tr('.', ',')
    end

    def tick(x, y)
      l(x - 0.9, y - 0.9, x + 0.9, y + 0.9, 'COTAS')
    end

    def cota_h(x1, x2, yref, y, mm)
      return if (x2 - x1).abs < 0.05
      s = y > yref ? 1 : -1
      [x1, x2].each { |x| l(x, yref + s * 1.0, x, y + s * 1.5, 'COTAS') }
      l(x1 - 1.5, y, x2 + 1.5, y, 'COTAS')
      tick(x1, y)
      tick(x2, y)
      t = fmt_cm(mm)
      if x2 - x1 >= larg(t, TD) + 1
        txt(t, (x1 + x2) / 2.0, y + 0.8, TD, 'COTAS', 1)
      else
        txt(t, x2 + 1.8, y + 0.8, TD, 'COTAS', 0)
      end
    end

    def cota_v(y1, y2, xref, x, mm)
      return if (y2 - y1).abs < 0.05
      s = x > xref ? 1 : -1
      [y1, y2].each { |y| l(xref + s * 1.0, y, x + s * 1.5, y, 'COTAS') }
      l(x, y1 - 1.5, x, y2 + 1.5, 'COTAS')
      tick(x, y1)
      tick(x, y2)
      t = fmt_cm(mm)
      if y2 - y1 >= larg(t, TD) + 1
        txt(t, x - 0.8, (y1 + y2) / 2.0, TD, 'COTAS', 1, 90)
      else
        txt(t, x - 0.8, y2 + 1.8, TD, 'COTAS', 0, 90)
      end
    end

    def cadeia?(q)
      q.size > 2 && q.size <= MAX_CADEIA + 1
    end

    # ------------------------------------------------------------ folha
    def folha
      rect(0, 0, 420, 297, 'FOLHA')
      rect(FX0, FY0, FX1, FY1, 'FOLHA')
      txt('FORMATO A3 (420x297mm) - NBR 16752', FX0 - 3, FY0 + 2, 1.8, 'FOLHA', 0, 90)
    end

    def carimbo_e_tabelas
      tipo = @p[:tipo].to_s
      x0 = FX1 - CW
      x1 = FX1
      xm = x0 + CW / 2.0
      y0 = FY0
      y1 = FY0 + 48

      rect(x0, y0, x1, y1)
      l(xm, y0, xm, y1)
      l(x0, y0 + 24, xm, y0 + 24)
      txt('CONTEÚDO:', x0 + 2, y0 + 44, 1.8)
      txt("DETALHAMENTO DE #{tipo}", x0 + 2, y0 + 38, 2.5)
      grande = "#{tipo} #{@p[:nome]}".strip
      hg = [6.0, (CW / 2.0 - 8) / [larg(grande, 1.0), 0.1].max].min
      txt(grande, x0 + 4, y0 + 12 - hg / 2.0, hg)

      [12, 24, 36].each { |dy| l(xm, y0 + dy, x1, y0 + dy) }
      txt('OBRA:', xm + 2, y0 + 44, 1.8)
      txt(@c[:obra], xm + 2, y0 + 38.5, 2.5)
      txt('LOCAL:', xm + 2, y0 + 32, 1.8)
      txt(@c[:local], xm + 2, y0 + 26.5, 2.5)
      txt('ARQUIVO:', xm + 2, y0 + 20, 1.8)
      txt(nome_arquivo, xm + 2, y0 + 14.5, 2.5)
      c1 = xm + 35
      c2 = xm + 65
      l(c1, y0, c1, y0 + 12)
      l(c2, y0, c2, y0 + 12)
      txt('ESCALA:', xm + 2, y0 + 8.5, 1.8)
      txt('INDICADA', xm + 4, y0 + 3, 2.2)
      txt('DATA:', c1 + 2, y0 + 8.5, 1.8)
      txt(@c[:data], c1 + 3, y0 + 3, 2.2)
      txt('REVISÃO:', c2 + 2, y0 + 8.5, 1.8)
      txt(@c[:revisao], x1 - 4, y0 + 2, 5, 'TEXTO', 2)

      # revisões
      revs = Array(@c[:revisoes]).map(&:to_s).reject(&:empty?)
      yr = y1
      altr = 5.0 * (revs.size + 1)
      rect(x0, yr, x1, yr + altr)
      (1..revs.size).each { |k| l(x0, yr + 5 * k, x1, yr + 5 * k) }
      txt('REVISÕES', (x0 + x1) / 2, yr + altr - 3.6, 2.0, 'TEXTO', 1)
      revs.each_with_index do |r, k|
        txt(r, (x0 + x1) / 2, yr + altr - 5 * (k + 1) - 3.6, 1.8, 'TEXTO', 1)
      end

      # resumo
      yb = yr + altr + 2
      larguras = [22, 20, 20, 22, 14, 24, 24, 22, 22]
      cab = [['Peças'], ['Largura', '(cm)'], ['Altura', '(cm)'], ['Comp.', '(cm)'],
             ['Qtd.'], ['Volume', 'Unit. (m³)'], ['Volume', 'Total (m³)'],
             ['Peso', 'Unit. (t)'], ['Fck', '(MPa)']]
      peso = @vol * @c[:peso_esp].to_f
      vals = [@p[:nome], fmt_cm(@A), fmt_cm(@B), fmt_cm(@L), @p[:qtd].to_s,
              fmt2(@vol), fmt2(@vol * @p[:qtd].to_i), fmt2(peso), @c[:fck].to_s]
      rect(x0, yb, x1, yb + 19)
      l(x0, yb + 5, x1, yb + 5)
      l(x0, yb + 14, x1, yb + 14)
      plural = @p[:tipo_plural].to_s
      txt("RESUMO - #{plural} PRÉ-FABRICADOS".squeeze(' '), (x0 + x1) / 2, yb + 15.4, 2.2, 'TEXTO', 1)
      x = x0
      larguras.each_with_index do |w, k|
        l(x, yb, x, yb + 14) if k > 0
        cx = x + w / 2.0
        if cab[k].size == 1
          txt(cab[k][0], cx, yb + 8.6, 1.8, 'TEXTO', 1)
        else
          txt(cab[k][0], cx, yb + 10.4, 1.8, 'TEXTO', 1)
          txt(cab[k][1], cx, yb + 6.8, 1.8, 'TEXTO', 1)
        end
        txt(vals[k], cx, yb + 1.6, 1.8, 'TEXTO', 1)
        x += w
      end
      yb + 19
    end

    # ------------------------------------------------------------ vistas
    def info(vista, alt)
      hs = @verts.map { |q| vista.proj(q)[0] }
      vs = @verts.map { |q| vista.proj(q)[1] }
      ip = @insertos.flat_map { |i| i[:arestas].flatten(1) }.map { |q| vista.proj(q) }
      {
        hq: G.quebras(hs, TOL),
        vq: G.quebras(vs, TOL),
        ptop: ip.empty? ? 0.0 : [ip.map { |q| q[1] }.max - alt, 0.0].max,
        pbot: ip.empty? ? 0.0 : [-ip.map { |q| q[1] }.min, 0.0].max
      }
    end

    def centros_insertos(vista)
      cs = @insertos.map do |i|
        xs = i[:arestas].flatten(1).map { |q| vista.proj(q)[0] }
        (xs.min + xs.max) / 2.0
      end
      G.quebras(cs, TOL)
    end

    def vistas(x0, x1, y0, y1)
      sup = info(@vs, @A)
      lat = info(@vl, @B)
      ins = centros_insertos(@vl)
      sup_rows = cadeia?(sup[:hq]) ? 2 : 1
      lat_rows = (cadeia?(lat[:hq]) ? 1 : 0) + (ins.empty? ? 0 : 1) + 1

      altura = lambda do |s|
        (15 + sup_rows * ROW + 2) + (sup[:ptop] + @A + sup[:pbot]) / s + 6 +
          (5 + lat_rows * ROW + 2 + 8) + (lat[:ptop] + @B + lat[:pbot]) / s + 9
      end
      s = ESCALAS.find { |e| @L / e <= x1 - x0 && altura.call(e) <= y1 - y0 } || ESCALAS.last
      @escala_vistas = s

      # -- vista superior
      txt("#{@p[:nome]} (#{@p[:qtd]}x)", FX0 + 4, y1 - 4.5, 3.5)
      txt("ESCALA: 1:#{s}", FX0 + 4, y1 - 8.5, 2.0)
      txt('VISTA SUPERIOR', FX0 + 4, y1 - 12, 2.0)
      topo = y1 - 15 - sup_rows * ROW - 2 - sup[:ptop] / s
      oy = topo - @A / s
      desenhar_vista(@vs, x0, oy, s)
      cotas_vista(sup, x0, oy, topo + sup[:ptop] / s, s, @A, [])
      fundo = oy - sup[:pbot] / s

      # -- vista lateral
      yt = fundo - 6
      txt('VISTA LATERAL', FX0 + 4, yt - 3.5, 2.5)
      topo = yt - 5 - (lat_rows * ROW + 2) - 8 - lat[:ptop] / s
      oy = topo - @B / s
      desenhar_vista(@vl, x0, oy, s)
      rotulos_insertos(@vl, x0, oy, s)
      cotas_vista(lat, x0, oy, topo + lat[:ptop] / s + 8, s, @B, ins)

      # marcas de corte
      ytop = topo + lat[:ptop] / s
      ybot = oy - lat[:pbot] / s
      @cortes.each do |c|
        x = x0 + c[:pos] / s
        [[ytop + 1, ytop + 6], [ybot - 1, ybot - 6]].each do |ya, yb|
          l(x, ya, x, yb, 'CORTE')
          l(x, yb, x - 2.5, yb, 'CORTE')
          txt(c[:letra], x + 0.8, (ya + yb) / 2.0 - 1.2, 2.5, 'CORTE')
        end
      end
    end

    def desenhar_vista(vista, ox, oy, s)
      ocl = G::Oclusao.new(@tris, vista)
      vis, hid = G.classificar(@arestas, vista, ocl, 0.8 * s)
      pp = lambda { |q| [ox + q[0] / s, oy + q[1] / s] }
      vis.each { |a, b| pa = pp.call(a); pb = pp.call(b); l(pa[0], pa[1], pb[0], pb[1], 'CONTORNO') }
      hid.each { |a, b| pa = pp.call(a); pb = pp.call(b); l(pa[0], pa[1], pb[0], pb[1], 'OCULTO') }
      @insertos.each do |i|
        G.dedup(i[:arestas].map { |a, b| [vista.proj(a), vista.proj(b)] }).each do |a, b|
          pa = pp.call(a)
          pb = pp.call(b)
          l(pa[0], pa[1], pb[0], pb[1], 'INSERTOS')
        end
      end
    end

    def rotulos_insertos(vista, ox, oy, s)
      usados = []
      @insertos.each do |i|
        pts = i[:arestas].flatten(1).map { |q| vista.proj(q) }
        x = ox + pts.map { |q| q[0] }.max / s + 1.0
        y = oy + pts.map { |q| q[1] }.max / s
        next if usados.any? { |n, ux, uy| n == i[:nome] && (ux - x).abs < 1 && (uy - y).abs < 1 }
        usados << [i[:nome], x, y]
        txt(i[:nome].upcase, x, y - 1.0, 1.8, 'INSERTOS')
      end
    end

    # Cotas horizontais acima da vista e verticais à esquerda.
    # base = y a partir do qual começam as linhas de cota horizontais.
    def cotas_vista(inf, ox, oy, base, s, alt, ins)
      topo = oy + alt / s
      fx = lambda { |v| ox + v / s }
      fy = lambda { |v| oy + v / s }
      linha = 0
      yrow = lambda { |k| base + 4 + k * ROW }
      cabe = lambda { |q, minimo| q.each_cons(2).all? { |a, b| (b - a) / s >= minimo } }
      if cadeia?(inf[:hq]) && cabe.call(inf[:hq], 2.0)
        inf[:hq].each_cons(2) { |a, b| cota_h(fx.call(a), fx.call(b), topo, yrow.call(linha), b - a) }
        linha += 1
      end
      unless ins.empty?
        pts = G.quebras([0.0] + ins + [@L], TOL)
        pts.each_cons(2) { |a, b| cota_h(fx.call(a), fx.call(b), topo, yrow.call(linha), b - a) }
        linha += 1
      end
      cota_h(fx.call(0), fx.call(@L), topo, yrow.call(linha), @L)

      col = 0
      if cadeia?(inf[:vq]) && cabe.call(inf[:vq], 4.0)
        inf[:vq].each_cons(2) { |a, b| cota_v(fy.call(a), fy.call(b), ox, ox - 4, b - a) }
        col += 1
      end
      cota_v(fy.call(0), fy.call(alt), ox, ox - 4 - col * ROW, alt)
    end

    # ------------------------------------------------------------ cortes
    def assinatura(segs)
      cs = G.cantos(segs)
      xs = G.quebras(cs.map { |q| q[0] }, 1.0).map(&:round)
      ys = G.quebras(cs.map { |q| q[1] }, 1.0).map(&:round)
      area = G.area_secao(segs, [[@A, @B].max / 200.0, 0.5].max)
      [xs, ys, (area / [@A * @B, 1e-9].max * 200).round]
    end

    def calcular_cortes
      xs = G.quebras(@verts.map { |q| q[@il] }, 0.1)
      lista = []
      xs.each_cons(2) do |a, b|
        next if b - a < 10
        c = (a + b) / 2.0
        segs = G.corte(@tris, @il, c, @ia, @ib)
        next if segs.size < 3
        sig = assinatura(segs)
        if lista.last && lista.last[:sig] == sig
          lista.last[:comp] += b - a
        else
          lista << { sig: sig, pos: c, segs: segs, comp: b - a }
        end
      end
      unicos = []
      lista.each do |it|
        u = unicos.find { |x| x[:sig] == it[:sig] }
        if u
          u[:comp] += it[:comp]
        else
          unicos << it.dup
        end
      end
      unicos = unicos.sort_by { |u| -u[:comp] }.first(4).sort_by { |u| u[:pos] } if unicos.size > 4
      unicos.each_with_index { |u, k| u[:letra] = ('A'.ord + k).chr }
      unicos
    end

    def desenhar_cortes(x0, x1, y0, y1)
      return if @cortes.empty?
      n = @cortes.size
      slot = (x1 - x0) / n
      bbs = @cortes.map do |c|
        pts = c[:segs].flatten(1)
        [pts.map { |q| q[0] }.min, pts.map { |q| q[0] }.max,
         pts.map { |q| q[1] }.min, pts.map { |q| q[1] }.max]
      end
      wmax = bbs.map { |b| b[1] - b[0] }.max
      hmax = bbs.map { |b| b[3] - b[2] }.max
      s = ESCALAS.find { |e| wmax / e + 20 <= slot && hmax / e + 26 <= y1 - y0 } || ESCALAS.last
      @escala_cortes = s

      @cortes.each_with_index do |c, k|
        amin, amax, bmin, bmax = bbs[k]
        ox = x0 + k * slot + 16
        oy = y0 + 13
        pp = lambda { |q| [ox + (q[0] - amin) / s, oy + (q[1] - bmin) / s] }
        c[:segs].each { |a, b| pa = pp.call(a); pb = pp.call(b); l(pa[0], pa[1], pb[0], pb[1], 'CONTORNO') }
        G.varredura(c[:segs], 1.5 * s, 45).each do |a, b|
          pa = pp.call(a)
          pb = pp.call(b)
          l(pa[0], pa[1], pb[0], pb[1], 'HACHURA')
        end
        w = (amax - amin) / s
        h = (bmax - bmin) / s
        txt("CORTE #{c[:letra]}-#{c[:letra]}", ox - 6, oy + h + 9, 3.0)
        txt("ESCALA: 1:#{s}", ox - 6, oy + h + 5, 2.0)

        pts = G.cantos(c[:segs])
        qa = G.quebras(pts.map { |q| q[0] }, TOL)
        qb = G.quebras(pts.map { |q| q[1] }, TOL)
        fx = lambda { |v| ox + (v - amin) / s }
        fy = lambda { |v| oy + (v - bmin) / s }
        lin = 0
        if cadeia?(qa)
          qa.each_cons(2) { |a, b| cota_h(fx.call(a), fx.call(b), oy, oy - 4, b - a) }
          lin = 1
        end
        cota_h(ox, ox + w, oy, oy - 4 - lin * ROW, amax - amin)
        col = 0
        if cadeia?(qb)
          qb.each_cons(2) { |a, b| cota_v(fy.call(a), fy.call(b), ox, ox - 4, b - a) }
          col = 1
        end
        cota_v(oy, oy + h, ox, ox - 4 - col * ROW, bmax - bmin)
      end
    end

    # ------------------------------------------------------------ 3D
    def calcular_iso
      ocl = G::Oclusao.new(@tris, @vi)
      vis, = G.classificar(@arestas, @vi, ocl, [@L, @A, @B].max / 150.0)
      ins = @insertos.flat_map { |i| i[:arestas].map { |a, b| [@vi.proj(a), @vi.proj(b)] } }
      pts = (vis + ins).flatten(1)
      xs = pts.map { |q| q[0] }
      ys = pts.map { |q| q[1] }
      { vis: vis, ins: ins, x0: xs.min, y0: ys.min,
        w: [xs.max - xs.min, 1e-6].max, h: [ys.max - ys.min, 1e-6].max }
    end

    def fator(iso, box)
      [(box[1] - box[0]) / iso[:w], (box[3] - box[2] - 6) / iso[:h]].min
    end

    def desenhar_iso(iso, box, k)
      w = iso[:w] * k
      h = iso[:h] * k
      ox = (box[0] + box[1]) / 2.0 - w / 2.0
      oy = box[2] + 6 + ((box[3] - box[2] - 6) - h) / 2.0
      pp = lambda { |q| [ox + (q[0] - iso[:x0]) * k, oy + (q[1] - iso[:y0]) * k] }
      iso[:vis].each { |a, b| pa = pp.call(a); pb = pp.call(b); l(pa[0], pa[1], pb[0], pb[1], 'MODELO3D') }
      iso[:ins].each { |a, b| pa = pp.call(a); pb = pp.call(b); l(pa[0], pa[1], pb[0], pb[1], 'INSERTOS') }
      txt('MODELO 3D', (box[0] + box[1]) / 2.0, oy - 4.5, 2.2, 'TEXTO', 1)
    end
  end
end
