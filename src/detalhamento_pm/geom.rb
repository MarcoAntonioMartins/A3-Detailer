# encoding: UTF-8
# Núcleo de geometria em Ruby puro (não depende da API do SketchUp).
# Unidades: milímetros. Pontos: [x, y, z].
module DetalhamentoPM
  module G
    module_function

    def sub(a, b);  [a[0] - b[0], a[1] - b[1], a[2] - b[2]]; end
    def add(a, b);  [a[0] + b[0], a[1] + b[1], a[2] + b[2]]; end
    def mul(a, s);  [a[0] * s, a[1] * s, a[2] * s]; end
    def dot(a, b);  a[0] * b[0] + a[1] * b[1] + a[2] * b[2]; end
    def len(a);     Math.sqrt(dot(a, a)); end

    def cross(a, b)
      [a[1] * b[2] - a[2] * b[1],
       a[2] * b[0] - a[0] * b[2],
       a[0] * b[1] - a[1] * b[0]]
    end

    def norm(a)
      l = len(a)
      l < 1e-12 ? a : mul(a, 1.0 / l)
    end

    def lerp2(a, b, t)
      [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]
    end

    # Valores distintos (ordenados), unindo os que ficam a menos de tol.
    def quebras(vals, tol)
      res = []
      vals.sort.each { |v| res << v if res.empty? || v - res.last > tol }
      res
    end

    # Volume de uma malha fechada (mm³), pelo teorema da divergência.
    def volume(tris)
      v = 0.0
      tris.each { |a, b, c| v += dot(a, cross(b, c)) / 6.0 }
      v.abs
    end

    # ------------------------------------------------------------------
    # Vista ortográfica: r = direita no papel, u = para cima no papel.
    # d = sentido do olhar (do observador para a peça).
    class Vista
      attr_reader :r, :u, :d

      def initialize(r, u)
        @r = G.norm(r)
        @u = G.norm(u)
        @d = G.cross(@u, @r)
      end

      def proj(p)
        [G.dot(p, @r), G.dot(p, @u)]
      end

      # Quanto maior, mais perto do observador.
      def prof(p)
        -G.dot(p, @d)
      end
    end

    # ------------------------------------------------------------------
    # Teste de oclusão: um ponto está oculto se algum triângulo fica entre
    # ele e o observador.
    class Oclusao
      def initialize(tris, vista)
        @v   = vista
        @dir = G.mul(vista.d, -1.0)
        @tris = []
        tris.each do |a, b, c|
          e1 = G.sub(b, a)
          e2 = G.sub(c, a)
          area2 = G.len(G.cross(e1, e2))
          next if area2 < 1e-9
          # face vista de lado (paralela ao olhar) não oculta nada
          next if G.dot(G.cross(e1, e2), @dir).abs < 1e-7 * area2
          pa = vista.proj(a)
          pb = vista.proj(b)
          pc = vista.proj(c)
          @tris << [a, e1, e2, area2,
                    [pa[0], pb[0], pc[0]].min, [pa[0], pb[0], pc[0]].max,
                    [pa[1], pb[1], pc[1]].min, [pa[1], pb[1], pc[1]].max,
                    [vista.prof(a), vista.prof(b), vista.prof(c)].max]
        end
      end

      def oculto?(p, eps = 0.5)
        q = @v.proj(p)
        z = @v.prof(p)
        dir = @dir
        @tris.each do |a, e1, e2, area2, x0, x1, y0, y1, zmax|
          next if q[0] < x0 - eps || q[0] > x1 + eps
          next if q[1] < y0 - eps || q[1] > y1 + eps
          next if zmax <= z + eps
          h   = G.cross(dir, e2)
          det = G.dot(e1, h)
          next if det.abs < 1e-9 * area2
          inv = 1.0 / det
          s = G.sub(p, a)
          u = inv * G.dot(s, h)
          next if u < -1e-6 || u > 1.0 + 1e-6
          qv = G.cross(s, e1)
          v = inv * G.dot(dir, qv)
          next if v < -1e-6 || u + v > 1.0 + 1e-6
          t = inv * G.dot(e2, qv)
          return true if t > eps
        end
        false
      end
    end

    # Divide o segmento a-b em trechos contínuos segundo o teste do bloco.
    # Devolve [[t0, t1, flag], ...]
    def trechos(n)
      flags = (0...n).map { |i| yield((i + 0.5) / n) }
      res = []
      i = 0
      while i < n
        j = i
        j += 1 while j + 1 < n && flags[j + 1] == flags[i]
        t0 = i.zero? ? 0.0 : i.to_f / n
        t1 = j == n - 1 ? 1.0 : (j + 1).to_f / n
        res << [t0, t1, flags[i]]
        i = j + 1
      end
      res
    end

    def dist_ponto_seg(p, a, b)
      dx = b[0] - a[0]
      dy = b[1] - a[1]
      l2 = dx * dx + dy * dy
      t = l2 < 1e-12 ? 0.0 : ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / l2
      t = 0.0 if t < 0
      t = 1.0 if t > 1
      Math.hypot(p[0] - (a[0] + t * dx), p[1] - (a[1] + t * dy))
    end

    def dedup(segs)
      vistos = {}
      segs.select do |a, b|
        ka = [a[0].round(1), a[1].round(1)]
        kb = [b[0].round(1), b[1].round(1)]
        next false if ka == kb
        k = [ka, kb].sort
        next false if vistos[k]
        vistos[k] = true
      end
    end

    # Classifica as arestas em visíveis e ocultas (coordenadas projetadas,
    # em mm reais). passo = tamanho de amostragem em mm reais.
    def classificar(arestas, vista, ocl, passo)
      vis = []
      hid = []
      arestas.each do |a, b|
        pa = vista.proj(a)
        pb = vista.proj(b)
        l = Math.hypot(pb[0] - pa[0], pb[1] - pa[1])
        next if l < 0.05
        n = [[(l / passo).ceil, 3].max, 80].min
        ab = sub(b, a)
        trechos(n) { |t| ocl.oculto?(add(a, mul(ab, t))) }.each do |t0, t1, oc|
          (oc ? hid : vis) << [lerp2(pa, pb, t0), lerp2(pa, pb, t1)]
        end
      end
      vis = dedup(vis)
      hid = dedup(hid)
      # remove trechos ocultos que caem exatamente sobre linhas visíveis
      tol = [passo * 0.1, 0.5].max
      hid2 = []
      hid.each do |a, b|
        l = Math.hypot(b[0] - a[0], b[1] - a[1])
        n = [[(l / passo).ceil, 2].max, 60].min
        trechos(n) do |t|
          p = lerp2(a, b, t)
          vis.none? { |va, vb| dist_ponto_seg(p, va, vb) < tol }
        end.each do |t0, t1, livre|
          hid2 << [lerp2(a, b, t0), lerp2(a, b, t1)] if livre
        end
      end
      [vis, hid2]
    end

    # ------------------------------------------------------------------
    # Corte por um plano perpendicular ao eixo `eixo` na coordenada c.
    # Devolve segmentos 2D nas coordenadas (ia, ib).
    def corte(tris, eixo, c, ia, ib)
      segs = []
      tris.each do |tri|
        d = tri.map { |p| p[eixo] - c }
        pts = []
        3.times do |k|
          d1 = d[k]
          d2 = d[(k + 1) % 3]
          next unless (d1 < 0 && d2 > 0) || (d1 > 0 && d2 < 0)
          p1 = tri[k]
          p2 = tri[(k + 1) % 3]
          t = d1 / (d1 - d2)
          q = add(p1, mul(sub(p2, p1), t))
          pts << [q[ia], q[ib]]
        end
        segs << pts if pts.size == 2
      end
      segs
    end

    # Linhas de varredura (regra par-ímpar) dentro de um contorno formado
    # por segmentos soltos. Devolve segmentos [a, b].
    def varredura(segs, espac, ang_graus)
      ang = ang_graus * Math::PI / 180.0
      ca = Math.cos(ang)
      sa = Math.sin(ang)
      rot = lambda { |p| [p[0] * ca + p[1] * sa, -p[0] * sa + p[1] * ca] }
      inv = lambda { |p| [p[0] * ca - p[1] * sa, p[0] * sa + p[1] * ca] }
      rs = segs.map { |a, b| [rot.call(a), rot.call(b)] }
      return [] if rs.empty?
      ys = rs.flatten(1).map { |p| p[1] }
      y0 = ys.min
      y1 = ys.max
      out = []
      y = (y0 / espac).floor * espac + espac * 0.5
      while y < y1
        xs = []
        rs.each do |a, b|
          lo, hi = a[1] < b[1] ? [a, b] : [b, a]
          next if hi[1] - lo[1] < 1e-12
          next unless y >= lo[1] && y < hi[1]
          xs << lo[0] + (y - lo[1]) * (hi[0] - lo[0]) / (hi[1] - lo[1])
        end
        xs.sort!
        xs.each_slice(2) do |xa, xb|
          out << [inv.call([xa, y]), inv.call([xb, y])] if xb && xb - xa > 1e-9
        end
        y += espac
      end
      out
    end

    # Cantos reais de um contorno: pontos onde chegam segmentos não
    # colineares (descarta pontos intermediários criados pela triangulação).
    def cantos(segs)
      dirs = Hash.new { |h, k| h[k] = [] }
      pts = {}
      segs.each do |a, b|
        dx = b[0] - a[0]
        dy = b[1] - a[1]
        l = Math.hypot(dx, dy)
        next if l < 1e-9
        d = [dx / l, dy / l]
        [a, b].each do |p|
          k = [(p[0] * 100).round, (p[1] * 100).round]
          dirs[k] << d
          pts[k] = p
        end
      end
      dirs.select do |_, ds|
        ds.any? { |u| ds.any? { |v| (u[0] * v[1] - u[1] * v[0]).abs > 1e-3 } }
      end.keys.map { |k| pts[k] }
    end

    def area_secao(segs, espac)
      varredura(segs, espac, 0).inject(0.0) { |s, (a, b)| s + (b[0] - a[0]).abs * espac }
    end
  end
end
