%% =========================================================================
%  ABC ALGORİTMASI İLE PV-RÜZGAR-BATARYA HİBRİT SİSTEMİ
%  OPTİMAL BOYUTLANDIRMA
%  =========================================================================

clc; clear; close all;
rng(42);   % Tekrarlanabilirlik için sabit tohum

%% =========================================================================
%  1. GİRİŞ VERİLERİ (24 Saatlik Profil)
% =========================================================================

PLoad = [0.8,0.8,0.8,0.8,1.0,1.5,2.0,2.0,2.0,2.0,2.0,2.0, ...
         1.8,1.6,1.8,2.0,1.8,1.6,1.2,1.0,0.8,0.8,0.8,0.8];  % kW

V     = [4.5,4.4,4.3,4.2,4.4,4.6,5.0,5.5,6.0,5.8,5.6,5.4, ...
         4.6,4.2,3.8,4.0,4.4,4.8,5.2,5.4,5.6,5.8,6.0,5.9];  % m/s

G_t   = [0,0,0,0,50,100,200,400,600,700,800,800, ...
         700,600,400,200,100,50,0,0,0,0,0,0];                 % W/m²

Tamb  = [24.7,24.5,24.3,24.4,24.5,26.5,27.5,28,28.5,28.8,29,29.7, ...
         29.8,30,29.8,29.5,29,27.7,26.5,24.8,25,24.8,24.6,24.8];  % °C

T = 24;            % Saat sayısı
t_ax = 1:T;        % Saat ekseni

%% =========================================================================
%  2. SİSTEM PARAMETRELERİ
% =========================================================================

% --- 2.1 PV Panel (Denklem 1-2) ---
PV.P_rated  = 0.305;    % Nominal güç (kW/panel)
PV.G_STC    = 1000;     % STC ışınımı (W/m²)
PV.T_STC    = 25;       % STC sıcaklığı (°C)
PV.alpha_T  = -0.0045;  % Güç-sıcaklık katsayısı (/°C)
PV.NOCT     = 45;       % Nominal çalışma hücre sıcaklığı (°C)
PV.L        = 20;       % Ömür (yıl)
PV.C_cap    = 300;      % Sermaye maliyeti ($/panel)
PV.C_rep    = 300;      % Yenileme maliyeti ($/panel)
PV.C_om     = 10;       % Yıllık bakım maliyeti ($/panel/yıl)

% --- 2.2 Rüzgar Türbini (Denklem 3) ---
WT.P_rated  = 1.0;      % Nominal güç (kW/türbin)
WT.v_ci     = 2.5;      % Cut-in hızı (m/s)
WT.v_r      = 9.0;      % Nominal hız (m/s)
WT.v_co     = 25.0;     % Cut-out hızı (m/s)
WT.L        = 20;       % Ömür (yıl)
WT.C_cap    = 3200;     % Sermaye maliyeti ($/türbin)
WT.C_rep    = 1200;     % Yenileme maliyeti ($/türbin)
WT.C_om     = 96;       % Yıllık bakım maliyeti ($/türbin/yıl)

% --- 2.3 Batarya (Denklem 4-6) ---
BAT.E_cap   = 1.35;      % Birim kapasite (kWh/birim)
BAT.SOC_min = 0.20;     % Minimum SOC
BAT.SOC_max = 1.00;     % Maksimum SOC
BAT.eta_c   = 0.85;     % Şarj verimi
BAT.eta_d   = 1.0;      % Deşarj verimi (%100 verimli)
BAT.SOC0    = 0.50;     % Başlangıç SOC
BAT.L       = 10;       % Ömür (yıl)
BAT.C_cap   = 150;      % Sermaye maliyeti ($/birim)
BAT.C_rep   = 150;      % Yenileme maliyeti ($/birim)
BAT.C_om    = 5;        % Yıllık bakım maliyeti ($/birim/yıl)

% --- 2.4 İnverter ---
INV.L       = 10;       % Ömür (yıl)
INV.C_cap   = 800;      % Sermaye maliyeti ($)
INV.C_rep   = 800;      % Yenileme maliyeti ($)

%% =========================================================================
%  3. EKONOMİK PARAMETRELER
% =========================================================================

Econ.r      = 0.05;     % Yıllık indirim oranı
Econ.f      = 0.025;    % Yıllık enflasyon oranı
Econ.T_proj = 20;       % Proje ömrü (yıl)

% O&M Bugünkü Değer Faktörü (enflasyon dahil)
% PWF_OM = Σ_{n=1}^{T} [(1+f)/(1+r)]^n
PWF_OM = 0;
for n = 1:Econ.T_proj
    PWF_OM = PWF_OM + ((1 + Econ.f)/(1 + Econ.r))^n;
end

% Sermaye Geri Kazanım Faktörü (CRF)
% CRF = r*(1+r)^T / ((1+r)^T - 1)
Econ.CRF = (Econ.r * (1 + Econ.r)^Econ.T_proj) / ...
           ((1 + Econ.r)^Econ.T_proj - 1);

%% =========================================================================
%  4. OPTİMİZASYON KISITLARI
% =========================================================================

lb = [1,  1,  1 ];    % Alt sınırlar: [N_PV, N_WT, N_bat]
ub = [100, 20, 100];    % Üst sınırlar
D  = 3;               % Karar değişkeni sayısı: N_PV, N_WT, N_bat

LPSP_max = 0.05;      % Kabul edilebilir maksimum LPSP (%5)

%% =========================================================================
%  5. ABC ALGORİTMASI PARAMETRELERİ
% =========================================================================

SN      = 30;          % Toplam arı sayısı (Employed + Onlooker)
n_emp   = SN / 2;      % Çalışan (Employed) arı sayısı
n_onl   = SN / 2;      % İzleyici (Onlooker) arı sayısı
MaxIter = 200;         % Maksimum iterasyon sayısı
Limit   = n_emp * D;   % Scout tetikleme limiti

%% =========================================================================
%  6. BAŞLANGIÇ POPÜLASYONU
% =========================================================================

Food     = zeros(n_emp, D);
for i = 1:n_emp
    Food(i, :) = round(lb + rand(1, D) .* (ub - lb));
end

NPC_all  = zeros(n_emp, 1);
LPSP_all = zeros(n_emp, 1);
COE_all  = zeros(n_emp, 1);
fit_all  = zeros(n_emp, 1);
trial    = zeros(n_emp, 1);

for i = 1:n_emp
    [NPC_all(i), LPSP_all(i), COE_all(i)] = hesapla_NPC_LPSP(Food(i,:), ...
        PV, WT, BAT, INV, Econ, PWF_OM, G_t, Tamb, V, PLoad, T);
    fit_all(i) = hesapla_fitness(NPC_all(i), LPSP_all(i), LPSP_max);
end

% Global en iyi başlangıç çözümü
[~, best_idx] = max(fit_all);
best_sol      = Food(best_idx, :);
best_NPC      = NPC_all(best_idx);
best_LPSP     = LPSP_all(best_idx);
best_COE      = COE_all(best_idx);
best_fit      = fit_all(best_idx);

% Yakınsama geçmişi
best_NPC_hist = zeros(MaxIter, 1);
best_COE_hist = zeros(MaxIter, 1);

%% =========================================================================
%  7. ABC ANA DÖNGÜSÜ
% =========================================================================

fprintf('================================================================\n');
fprintf('  ABC ALGORİTMASI — PV-Rüzgar-Batarya Optimal Boyutlandırma\n');
fprintf('================================================================\n');
fprintf('  İter  |    En İyi NPC ($)    |  LPSP  | N_PV  N_WT  N_bat\n');
fprintf('----------------------------------------------------------------\n');

for iter = 1:MaxIter

    % ------------------------------------------------------------
    %  AŞAMA 1: EMPLOYED ARI (Çalışan Arı)
    %  Her çalışan arı, mevcut kaynağa yakın bir komşu üretir.
    % ------------------------------------------------------------
    for i = 1:n_emp
        k = randi(n_emp);
        while k == i,  k = randi(n_emp);  end

        j   = randi(D);
        phi = -1 + 2*rand();

        cand    = Food(i,:);
        cand(j) = Food(i,j) + phi*(Food(i,j) - Food(k,j));
        cand    = round(min(ub, max(lb, cand)));

        [cand_NPC, cand_LPSP, cand_COE] = hesapla_NPC_LPSP(cand, ...
            PV, WT, BAT, INV, Econ, PWF_OM, G_t, Tamb, V, PLoad, T);
        cand_fit = hesapla_fitness(cand_NPC, cand_LPSP, LPSP_max);

        if cand_fit > fit_all(i)
            Food(i,:)   = cand;
            NPC_all(i)  = cand_NPC;
            LPSP_all(i) = cand_LPSP;
            COE_all(i)  = cand_COE;
            fit_all(i)  = cand_fit;
            trial(i)    = 0;
        else
            trial(i) = trial(i) + 1;
        end
    end

    % ------------------------------------------------------------
    %  AŞAMA 2: ONLOOKER ARI (İzleyici Arı)
    %  Fitness orantılı olasılıkla (rulet) kaynak seçer.
    % ------------------------------------------------------------
    prob = fit_all / sum(fit_all);

    t = 0;  i = 1;
    while t < n_onl
        if rand() < prob(i)
            t = t + 1;

            k = randi(n_emp);
            while k == i,  k = randi(n_emp);  end
            j   = randi(D);
            phi = -1 + 2*rand();

            cand    = Food(i,:);
            cand(j) = Food(i,j) + phi*(Food(i,j) - Food(k,j));
            cand    = round(min(ub, max(lb, cand)));

            [cand_NPC, cand_LPSP, cand_COE] = hesapla_NPC_LPSP(cand, ...
                PV, WT, BAT, INV, Econ, PWF_OM, G_t, Tamb, V, PLoad, T);
            cand_fit = hesapla_fitness(cand_NPC, cand_LPSP, LPSP_max);

            if cand_fit > fit_all(i)
                Food(i,:)   = cand;
                NPC_all(i)  = cand_NPC;
                LPSP_all(i) = cand_LPSP;
                COE_all(i)  = cand_COE;
                fit_all(i)  = cand_fit;
                trial(i)    = 0;
            else
                trial(i) = trial(i) + 1;
            end
        end
        i = mod(i, n_emp) + 1;
    end

    % ------------------------------------------------------------
    %  AŞAMA 3: SCOUT ARI (Keşifçi Arı)
    %  Limit'i aşan kaynaklar rastgele yenilenir.
    % ------------------------------------------------------------
    for i = 1:n_emp
        if trial(i) >= Limit
            Food(i,:) = round(lb + rand(1,D).*(ub-lb));
            [NPC_all(i), LPSP_all(i), COE_all(i)] = hesapla_NPC_LPSP(Food(i,:), ...
                PV, WT, BAT, INV, Econ, PWF_OM, G_t, Tamb, V, PLoad, T);
            fit_all(i) = hesapla_fitness(NPC_all(i), LPSP_all(i), LPSP_max);
            trial(i)   = 0;
        end
    end

    % En iyi çözümü güncelle
    [iter_best_fit, idx] = max(fit_all);
    if iter_best_fit > best_fit
        best_fit  = iter_best_fit;
        best_sol  = Food(idx,:);
        best_NPC  = NPC_all(idx);
        best_LPSP = LPSP_all(idx);
        best_COE  = COE_all(idx);
    end

    best_NPC_hist(iter) = best_NPC;
    best_COE_hist(iter) = best_COE;

    if mod(iter,20)==0 || iter==1
        fprintf('  %4d  |  %16.2f      | %6.4f | %4d   %4d   %4d\n', ...
                iter, best_NPC, best_LPSP, ...
                best_sol(1), best_sol(2), best_sol(3));
    end
end

fprintf('================================================================\n');

%% =========================================================================
%  8. SONUÇLARIN YAZILMASI
% =========================================================================

fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════╗\n');
fprintf('║          OPTİMAL BOYUTLANDIRMA SONUÇLARI (ABC)          ║\n');
fprintf('╠══════════════════════════════════════════════════════════╣\n');
fprintf('║  PV Panel Sayısı          (N_PV)  : %-4d                ║\n', best_sol(1));
fprintf('║  Rüzgar Türbini Sayısı    (N_WT)  : %-4d                ║\n', best_sol(2));
fprintf('║  Batarya Sayısı           (N_bat) : %-4d                ║\n', best_sol(3));
fprintf('╠══════════════════════════════════════════════════════════╣\n');
fprintf('║  Net Present Cost (NPC)           : $%-10.2f         ║\n', best_NPC);
fprintf('║  Cost of Energy   (COE)           : $%-8.4f /kWh      ║\n', best_COE);
fprintf('║  LPSP                             : %-8.4f             ║\n', best_LPSP);
if best_LPSP <= LPSP_max
    fprintf('║  LPSP Kısıtı (≤ %.2f)            : SAĞLANIYOR ✓       ║\n', LPSP_max);
else
    fprintf('║  LPSP Kısıtı (≤ %.2f)            : SAĞLANAMADI ✗      ║\n', LPSP_max);
end
fprintf('╚══════════════════════════════════════════════════════════╝\n');

%% =========================================================================
%  9. OPTİMAL ÇÖZÜM İÇİN SAATLİK PROFİLLERİ HESAPLA
% =========================================================================

% PV hücre sıcaklığı ve çıkış gücü
T_cell = Tamb + ((PV.NOCT - 20)/800) .* G_t;
P_PV   = best_sol(1) .* PV.P_rated .* (G_t/PV.G_STC) .* ...
         (1 + PV.alpha_T .* (T_cell - PV.T_STC));
P_PV   = max(0, P_PV);

% Rüzgar türbini çıkış gücü
P_WT = zeros(1, T);
for h = 1:T
    v = V(h);
    if v < WT.v_ci || v > WT.v_co
        P_WT(h) = 0;
    elseif v >= WT.v_ci && v < WT.v_r
        P_WT(h) = best_sol(2)*WT.P_rated*((v-WT.v_ci)/(WT.v_r-WT.v_ci))^3;
    else
        P_WT(h) = best_sol(2)*WT.P_rated;
    end
end

% Batarya SOC ve güç açığı
E_bat_tot = best_sol(3) * BAT.E_cap;
SOC       = zeros(1, T+1);
SOC(1)    = BAT.SOC0;
P_def     = zeros(1, T);
P_bat     = zeros(1, T);   % (+) şarj, (-) deşarj
P_excess  = zeros(1, T);   % Fazla enerji (dökülme)

for h = 1:T
    P_net = P_PV(h) + P_WT(h) - PLoad(h);
    if P_net >= 0
        dSOC = (BAT.eta_c * P_net) / E_bat_tot;
        new_SOC = min(BAT.SOC_max, SOC(h) + dSOC);
        P_bat(h) = (new_SOC - SOC(h)) * E_bat_tot / BAT.eta_c;
        P_excess(h) = P_net - P_bat(h);
        SOC(h+1) = new_SOC;
    else
        avail = (SOC(h) - BAT.SOC_min) * E_bat_tot * BAT.eta_d;
        need  = abs(P_net);
        if avail >= need
            P_bat(h)  = -need;
            SOC(h+1)  = SOC(h) - need / E_bat_tot;
        else
            P_bat(h)  = -avail;
            P_def(h)  = need - avail;
            SOC(h+1)  = BAT.SOC_min;
        end
    end
end

%% =========================================================================
%  10. GRAFİKLER
% =========================================================================

% ---- RENK PALETİ ----
c_load   = [0.85, 0.33, 0.10];   % Turuncu-kırmızı (yük)
c_pv     = [0.93, 0.69, 0.13];   % Sarı-altın (PV)
c_wt     = [0.20, 0.63, 0.17];   % Yeşil (rüzgar)
c_bat    = [0.12, 0.47, 0.71];   % Mavi (batarya)
c_def    = [0.64, 0.08, 0.18];   % Koyu kırmızı (açık)
c_irr    = [0.96, 0.76, 0.05];   % Güneş sarısı
c_temp   = [0.89, 0.40, 0.00];   % Sıcaklık turuncusu
c_excess = [0.49, 0.18, 0.56];   % Mor (fazla)

% =====================================================================
%  ŞEKİL 1: GİRİŞ VERİLERİ — 4 Panel
% =====================================================================
figure('Name','Şekil 1 – Giriş Verileri','NumberTitle','off', ...
       'Color','w','Position',[100 100 1100 800]);

% --- (a) Yük Talebi ---
subplot(2,2,1);
area(t_ax, PLoad, 'FaceColor', c_load, 'FaceAlpha', 0.3, 'EdgeColor', c_load, 'LineWidth', 1.5);
hold on;
plot(t_ax, PLoad, 'o-', 'Color', c_load, 'MarkerFaceColor', c_load, ...
     'LineWidth', 1.8, 'MarkerSize', 6);
yline(mean(PLoad), '--k', sprintf('Ort: %.2f kW', mean(PLoad)), ...
      'LabelHorizontalAlignment','right','LineWidth',1);
xlabel('Saat (h)', 'FontSize', 11);
ylabel('Güç (kW)', 'FontSize', 11);
title('(a) Saatlik Yük Talebi', 'FontSize', 12, 'FontWeight', 'bold');
xlim([1 24]); ylim([0 2.5]); grid on; grid minor;
xticks(1:2:24); box on;

% --- (b) Rüzgar Hızı ---
subplot(2,2,2);
area(t_ax, V, 'FaceColor', c_wt, 'FaceAlpha', 0.2, 'EdgeColor', c_wt, 'LineWidth', 1.5);
hold on;
plot(t_ax, V, 's-', 'Color', c_wt, 'MarkerFaceColor', c_wt, ...
     'LineWidth', 1.8, 'MarkerSize', 6);
yline(WT.v_ci, ':b', 'v_{ci}=2.5', 'LabelHorizontalAlignment','left', 'LineWidth',1.2);
yline(WT.v_r,  ':r', 'v_{r}=9.0',  'LabelHorizontalAlignment','left', 'LineWidth',1.2);
xlabel('Saat (h)', 'FontSize', 11);
ylabel('Rüzgar Hızı (m/s)', 'FontSize', 11);
title('(b) Saatlik Rüzgar Hızı', 'FontSize', 12, 'FontWeight', 'bold');
xlim([1 24]); ylim([0 12]); grid on; grid minor;
xticks(1:2:24); box on;

% --- (c) Güneş Işınımı ---
subplot(2,2,3);
yyaxis left;
bar(t_ax, G_t, 0.6, 'FaceColor', c_irr, 'FaceAlpha', 0.75, 'EdgeColor', 'none');
ylabel('Işınım (W/m²)', 'FontSize', 11);
ylim([0 1100]);
yyaxis right;
plot(t_ax, Tamb, 'd-', 'Color', c_temp, 'MarkerFaceColor', c_temp, ...
     'LineWidth', 2, 'MarkerSize', 6);
ylabel('Ortam Sıcaklığı (°C)', 'FontSize', 11);
ylim([20 35]);
xlabel('Saat (h)', 'FontSize', 11);
title('(c) Güneş Işınımı & Ortam Sıcaklığı', 'FontSize', 12, 'FontWeight', 'bold');
legend({'Işınım G_t (W/m²)', 'Sıcaklık T_{amb} (°C)'}, 'Location', 'northwest', 'FontSize', 9);
xlim([0.5 24.5]); xticks(1:2:24); grid on; box on;

% --- (d) Hücre Sıcaklığı ---
subplot(2,2,4);
plot(t_ax, T_cell, '^-', 'Color', [0.5 0 0.5], 'MarkerFaceColor', [0.5 0 0.5], ...
     'LineWidth', 2, 'MarkerSize', 6);
hold on;
plot(t_ax, Tamb, 'd--', 'Color', c_temp, 'LineWidth', 1.5, 'MarkerSize', 5);
yline(PV.T_STC, ':k', 'T_{STC}=25°C', 'LabelHorizontalAlignment','right', 'LineWidth',1);
xlabel('Saat (h)', 'FontSize', 11);
ylabel('Sıcaklık (°C)', 'FontSize', 11);
title('(d) PV Hücre & Ortam Sıcaklığı', 'FontSize', 12, 'FontWeight', 'bold');
legend({'T_{hücre} (°C)', 'T_{amb} (°C)'}, 'Location', 'northwest', 'FontSize', 9);
xlim([1 24]); grid on; grid minor; xticks(1:2:24); box on;

sgtitle('Şekil 1 – Sistem Giriş Verileri (24 Saatlik Profil)', ...
        'FontSize', 14, 'FontWeight', 'bold');

% =====================================================================
%  ŞEKİL 2: ABC YAKINSAMA EĞRİSİ
% =====================================================================
figure('Name','Şekil 2 – ABC Yakınsama','NumberTitle','off', ...
       'Color','w','Position',[150 150 900 420]);

subplot(1,2,1);
plot(1:MaxIter, best_NPC_hist, '-', 'Color', [0.10 0.35 0.70], 'LineWidth', 2.2);
xlabel('İterasyon', 'FontSize', 12);
ylabel('En İyi NPC ($)', 'FontSize', 12);
title('(a) NPC Yakınsama Eğrisi', 'FontSize', 13, 'FontWeight', 'bold');
grid on; grid minor; box on;
xlim([1 MaxIter]);
text(MaxIter*0.6, best_NPC_hist(1)*0.98, ...
     sprintf('Final NPC: $%.2f', best_NPC), ...
     'FontSize', 10, 'Color', 'k', 'BackgroundColor', [0.9 0.95 1]);

subplot(1,2,2);
plot(1:MaxIter, best_COE_hist, '-', 'Color', [0.85 0.33 0.10], 'LineWidth', 2.2);
xlabel('İterasyon', 'FontSize', 12);
ylabel('En İyi COE ($/kWh)', 'FontSize', 12);
title('(b) COE Yakınsama Eğrisi', 'FontSize', 13, 'FontWeight', 'bold');
grid on; grid minor; box on;
xlim([1 MaxIter]);
text(MaxIter*0.6, best_COE_hist(1)*0.98, ...
     sprintf('Final COE: $%.4f', best_COE), ...
     'FontSize', 10, 'Color', 'k', 'BackgroundColor', [1 0.95 0.9]);

sgtitle('Şekil 2 – ABC Algoritması Yakınsama Performansı', ...
        'FontSize', 14, 'FontWeight', 'bold');

% =====================================================================
%  ŞEKİL 3: OPTİMAL SİSTEM — GÜÇ ÜRETİM PROFİLİ
% =====================================================================
figure('Name','Şekil 3 – Optimal Güç Üretimi','NumberTitle','off', ...
       'Color','w','Position',[200 200 1000 550]);

P_total_gen = P_PV + P_WT;

% Yığılı alan grafiği (stacked area)
hA = area(t_ax, [P_PV; P_WT]', 'FaceAlpha', 0.7);
hA(1).FaceColor = c_pv;
hA(1).EdgeColor = 'none';
hA(2).FaceColor = c_wt;
hA(2).EdgeColor = 'none';

hold on;
% Batarya etkisini ekle (deşarj = pozitif katkı)
P_bat_pos = max(0, -P_bat);   % Deşarj gücü (yüke katkı)
P_bat_neg = max(0,  P_bat);   % Şarj gücü (yükten alınan)

% Yük talebi çizgisi
plot(t_ax, PLoad, 'o-', 'Color', c_load, 'LineWidth', 2.5, ...
     'MarkerFaceColor', c_load, 'MarkerSize', 7, 'DisplayName', 'Yük Talebi');

% Toplam üretim
plot(t_ax, P_total_gen, 'k--', 'LineWidth', 1.5, 'DisplayName', 'Toplam Üretim (PV+WT)');

% Güç açığı
if any(P_def > 0)
    stem(t_ax, P_def, 'filled', 'Color', c_def, 'MarkerSize', 8, ...
         'LineWidth', 2, 'DisplayName', sprintf('Güç Açığı (LPSP=%.4f)', best_LPSP));
end

xlabel('Saat (h)', 'FontSize', 12);
ylabel('Güç (kW)', 'FontSize', 12);
title(sprintf('Şekil 3 – Optimal Sistemin Saatlik Güç Üretimi\n(N_{PV}=%d, N_{WT}=%d, N_{bat}=%d)', ...
      best_sol(1), best_sol(2), best_sol(3)), 'FontSize', 13, 'FontWeight', 'bold');

legend({'PV Üretimi (kW)', 'Rüzgar Üretimi (kW)', 'Yük Talebi (kW)', ...
        'Toplam Üretim (kW)', 'Güç Açığı (kW)'}, ...
       'Location', 'northeast', 'FontSize', 10, 'NumColumns', 2);
xlim([1 24]); xticks(1:2:24); grid on; grid minor; box on;

% =====================================================================
%  ŞEKİL 4: BATARYA SOC PROFİLİ
% =====================================================================
figure('Name','Şekil 4 – Batarya SOC','NumberTitle','off', ...
       'Color','w','Position',[250 250 1000 500]);

subplot(2,1,1);
SOC_plot = SOC(1:T);
area(t_ax, SOC_plot*100, 'FaceColor', c_bat, 'FaceAlpha', 0.35, ...
     'EdgeColor', c_bat, 'LineWidth', 2);
hold on;
plot(t_ax, SOC_plot*100, 'o-', 'Color', c_bat, 'MarkerFaceColor', c_bat, ...
     'MarkerSize', 7, 'LineWidth', 2);
yline(BAT.SOC_min*100, '--r', sprintf('SOC_{min}=%.0f%%', BAT.SOC_min*100), ...
      'LabelHorizontalAlignment','right', 'LineWidth', 1.5, 'FontSize', 10);
yline(BAT.SOC_max*100, '--g', sprintf('SOC_{max}=%.0f%%', BAT.SOC_max*100), ...
      'LabelHorizontalAlignment','right', 'LineWidth', 1.5, 'FontSize', 10);
yline(BAT.SOC0*100, ':k', sprintf('SOC_0=%.0f%%', BAT.SOC0*100), ...
      'LabelHorizontalAlignment','left', 'LineWidth', 1, 'FontSize', 9);
xlabel('Saat (h)', 'FontSize', 11);
ylabel('SOC (%)', 'FontSize', 11);
title(sprintf('(a) Batarya Şarj Durumu — N_{bat}=%d birim, Kapasite=%.1f kWh', ...
      best_sol(3), E_bat_tot), 'FontSize', 12, 'FontWeight', 'bold');
xlim([1 24]); ylim([0 110]); xticks(1:2:24); grid on; grid minor; box on;

subplot(2,1,2);
bar_colors = zeros(T, 3);
for h = 1:T
    if P_bat(h) >= 0
        bar_colors(h,:) = [0.18 0.55 0.18];   % Yeşil: şarj
    else
        bar_colors(h,:) = [0.80 0.15 0.15];   % Kırmızı: deşarj
    end
end
b = bar(t_ax, P_bat, 'FaceColor', 'flat', 'EdgeColor', 'none', 'BarWidth', 0.7);
b.CData = bar_colors;
hold on;
yline(0, '-k', 'LineWidth', 1.2);
xlabel('Saat (h)', 'FontSize', 11);
ylabel('Batarya Gücü (kW)', 'FontSize', 11);
title('(b) Batarya Şarj(+) / Deşarj(-) Gücü', 'FontSize', 12, 'FontWeight', 'bold');

% Efsane için yapay nesneler
h1 = patch(NaN, NaN, [0.18 0.55 0.18]); 
h2 = patch(NaN, NaN, [0.80 0.15 0.15]);
legend([h1, h2], {'Şarj (+)', 'Deşarj (-)'}, 'Location', 'northeast', 'FontSize', 10);
xlim([0.5 24.5]); xticks(1:2:24); grid on; grid minor; box on;

sgtitle('Şekil 4 – Batarya Enerji Yönetimi', 'FontSize', 14, 'FontWeight', 'bold');

% =====================================================================
%  ŞEKİL 5: GÜÇ DENGESİ (Energy Balance)
% =====================================================================
figure('Name','Şekil 5 – Güç Dengesi','NumberTitle','off', ...
       'Color','w','Position',[300 300 1000 500]);

% Enerji dengesi: Üretim - Tüketim - Şarj + Deşarj
P_supply = P_PV + P_WT + max(0, -P_bat);   % Sisteme sağlanan güç
P_demand = PLoad + max(0, P_bat);           % Sisteme talep edilen güç

subplot(2,1,1);
hold on;
area(t_ax, P_PV, 'FaceColor', c_pv,  'FaceAlpha', 0.6, 'EdgeColor','none', 'DisplayName','PV');
area(t_ax, P_PV + P_WT, 'FaceColor', c_wt, 'FaceAlpha', 0.5, 'EdgeColor','none', 'DisplayName','WT');
plot(t_ax, PLoad, 'o-', 'Color', c_load, 'LineWidth', 2.5, ...
     'MarkerFaceColor', c_load, 'MarkerSize', 7, 'DisplayName', 'Yük');
if any(P_def > 0)
    fill([t_ax, fliplr(t_ax)], [PLoad, fliplr(PLoad - P_def)], ...
         c_def, 'FaceAlpha', 0.4, 'EdgeColor','none', 'DisplayName','Güç Açığı');
end
xlabel('Saat (h)', 'FontSize', 11);
ylabel('Güç (kW)', 'FontSize', 11);
title('(a) Güç Üretim ve Tüketim Dengesi', 'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'northeast', 'FontSize', 9, 'NumColumns', 2);
xlim([1 24]); xticks(1:2:24); grid on; grid minor; box on;

subplot(2,1,2);
P_net_all = P_PV + P_WT - PLoad;
bar_c2 = zeros(T,3);
for h = 1:T
    if P_net_all(h) >= 0
        bar_c2(h,:) = [0.18 0.55 0.18];
    else
        bar_c2(h,:) = [0.80 0.15 0.15];
    end
end
b2 = bar(t_ax, P_net_all, 'FaceColor','flat', 'EdgeColor','none', 'BarWidth', 0.7);
b2.CData = bar_c2;
hold on;
yline(0, '-k', 'LineWidth', 1.2);
xlabel('Saat (h)', 'FontSize', 11);
ylabel('Net Güç (kW)', 'FontSize', 11);
title('(b) Net Güç Dengesi [P_{PV} + P_{WT} – P_{yük}]', 'FontSize', 12, 'FontWeight', 'bold');
h1=patch(NaN,NaN,[0.18 0.55 0.18]); h2=patch(NaN,NaN,[0.80 0.15 0.15]);
legend([h1,h2],{'Fazlalık (Şarj/Dökülme)','Açık (Deşarj/Kayıp)'}, ...
       'Location','northeast','FontSize',9);
xlim([0.5 24.5]); xticks(1:2:24); grid on; grid minor; box on;

sgtitle('Şekil 5 – Saatlik Güç Dengesi Analizi', 'FontSize', 14, 'FontWeight', 'bold');

% =====================================================================
%  ŞEKİL 6: MALİYET ANALİZİ — PASTA VE ÇUBUK
% =====================================================================
figure('Name','Şekil 6 – Maliyet Analizi','NumberTitle','off', ...
       'Color','w','Position',[350 350 1000 480]);

% Maliyet bileşenlerini hesapla
N_PV_opt  = best_sol(1);
N_WT_opt  = best_sol(2);
N_bat_opt = best_sol(3);

C_cap_PV  = N_PV_opt  * PV.C_cap;
C_cap_WT  = N_WT_opt  * WT.C_cap;
C_cap_bat = N_bat_opt * BAT.C_cap;
C_cap_inv = INV.C_cap;

C_om_PV   = N_PV_opt  * PV.C_om  * PWF_OM;
C_om_WT   = N_WT_opt  * WT.C_om  * PWF_OM;
C_om_bat  = N_bat_opt * BAT.C_om * PWF_OM;

C_rep_bat = 0;
for k = 1:(floor(Econ.T_proj/BAT.L)-1)
    C_rep_bat = C_rep_bat + N_bat_opt * BAT.C_rep / (1+Econ.r)^(k*BAT.L);
end
C_rep_inv = 0;
for k = 1:(floor(Econ.T_proj/INV.L)-1)
    C_rep_inv = C_rep_inv + INV.C_rep / (1+Econ.r)^(k*INV.L);
end

% --- (a) Bileşen bazlı pasta grafiği ---
subplot(1,2,1);
maliyet_labels = {'PV Sermaye','WT Sermaye','Bat Sermaye','İnv Sermaye', ...
                  'PV O&M','WT O&M','Bat O&M','Bat Yenileme','İnv Yenileme'};
maliyet_vals   = [C_cap_PV, C_cap_WT, C_cap_bat, C_cap_inv, ...
                  C_om_PV,  C_om_WT,  C_om_bat,  C_rep_bat, C_rep_inv];
% Sıfır olanları kaldır
mask = maliyet_vals > 0;
maliyet_labels = maliyet_labels(mask);
maliyet_vals   = maliyet_vals(mask);

pie(maliyet_vals, maliyet_labels);
title(sprintf('(a) NPC Bileşen Dağılımı\nToplam NPC: $%.2f', best_NPC), ...
      'FontSize', 11, 'FontWeight', 'bold');

% --- (b) Kategori bazlı çubuk grafiği ---
subplot(1,2,2);
cat_labels = {'Sermaye\nMaliyeti', 'O&M\nMaliyeti', 'Yenileme\nMaliyeti'};
cat_vals   = [C_cap_PV+C_cap_WT+C_cap_bat+C_cap_inv, ...
              C_om_PV+C_om_WT+C_om_bat, ...
              C_rep_bat+C_rep_inv];
cat_colors = [c_pv; c_wt; c_bat];

b3 = bar(categorical({'Sermaye','O&M','Yenileme'}), cat_vals, 0.6, ...
         'FaceColor','flat', 'EdgeColor','w', 'LineWidth',1.5);
b3.CData = cat_colors;

for k = 1:3
    text(k, cat_vals(k) + best_NPC*0.01, sprintf('$%.0f', cat_vals(k)), ...
         'HorizontalAlignment','center', 'FontSize', 10, 'FontWeight', 'bold');
end
ylabel('Maliyet ($)', 'FontSize', 12);
title('(b) Maliyet Kategorileri', 'FontSize', 12, 'FontWeight', 'bold');
grid on; grid minor; box on;

sgtitle('Şekil 6 – Optimal Sistem Maliyet Analizi', 'FontSize', 14, 'FontWeight', 'bold');

% =====================================================================
%  ŞEKİL 7: ABC POPÜLASYON DAĞILIMI (Son iterasyon)
% =====================================================================
figure('Name','Şekil 7 – Popülasyon Dağılımı','NumberTitle','off', ...
       'Color','w','Position',[400 400 900 500]);

subplot(1,3,1);
histogram(Food(:,1), 'BinWidth', 1, 'FaceColor', c_pv, 'EdgeColor','w', 'FaceAlpha', 0.85);
hold on;
xline(best_sol(1), '--r', sprintf('En iyi: %d', best_sol(1)), 'LineWidth', 2, 'FontSize', 10);
xlabel('N_{PV}', 'FontSize', 12);
ylabel('Frekans', 'FontSize', 12);
title('PV Panel Sayısı Dağılımı', 'FontSize', 11, 'FontWeight', 'bold');
grid on; box on;

subplot(1,3,2);
histogram(Food(:,2), 'BinWidth', 1, 'FaceColor', c_wt, 'EdgeColor','w', 'FaceAlpha', 0.85);
hold on;
xline(best_sol(2), '--r', sprintf('En iyi: %d', best_sol(2)), 'LineWidth', 2, 'FontSize', 10);
xlabel('N_{WT}', 'FontSize', 12);
ylabel('Frekans', 'FontSize', 12);
title('Rüzgar Türbini Sayısı Dağılımı', 'FontSize', 11, 'FontWeight', 'bold');
grid on; box on;

subplot(1,3,3);
histogram(Food(:,3), 'BinWidth', 1, 'FaceColor', c_bat, 'EdgeColor','w', 'FaceAlpha', 0.85);
hold on;
xline(best_sol(3), '--r', sprintf('En iyi: %d', best_sol(3)), 'LineWidth', 2, 'FontSize', 10);
xlabel('N_{bat}', 'FontSize', 12);
ylabel('Frekans', 'FontSize', 12);
title('Batarya Sayısı Dağılımı', 'FontSize', 11, 'FontWeight', 'bold');
grid on; box on;

sgtitle('Şekil 7 – ABC Son Popülasyonu Karar Değişkenleri Dağılımı', ...
        'FontSize', 14, 'FontWeight', 'bold');

% =====================================================================
%  ŞEKİL 8: ENERJİ KARŞILAMA ÖZETİ
% =====================================================================
figure('Name','Şekil 8 – Enerji Özeti','NumberTitle','off', ...
       'Color','w','Position',[450 450 900 480]);

% Günlük enerji değerleri
E_PV_gun  = sum(P_PV);
E_WT_gun  = sum(P_WT);
E_load_gun= sum(PLoad);
E_def_gun = sum(P_def);
E_met_gun = E_load_gun - E_def_gun;
E_exc_gun = sum(P_excess);

subplot(1,2,1);
kategoriler = {'PV Üretimi','WT Üretimi','Yük Talebi','Karşılanan','Karşılanamayan'};
degerler = [E_PV_gun, E_WT_gun, E_load_gun, E_met_gun, E_def_gun];
renkler = [c_pv; c_wt; c_load; [0.18 0.55 0.18]; c_def];
b4 = bar(categorical(kategoriler), degerler, 0.65, 'FaceColor','flat','EdgeColor','w','LineWidth',1.5);
b4.CData = renkler;
for k = 1:5
    text(k, degerler(k) + 0.05, sprintf('%.2f\nkWh', degerler(k)), ...
         'HorizontalAlignment','center','FontSize',9,'FontWeight','bold');
end
ylabel('Enerji (kWh/gün)', 'FontSize', 12);
title('(a) Günlük Enerji Dengesi', 'FontSize', 12, 'FontWeight', 'bold');
grid on; grid minor; box on; ylim([0 max(degerler)*1.25]);

subplot(1,2,2);
% Enerji kaynak payı pasta
kaynak_labels = {sprintf('PV (%.1f kWh)', E_PV_gun), ...
                 sprintf('WT (%.1f kWh)', E_WT_gun)};
kaynak_vals = [E_PV_gun, E_WT_gun];
p = pie(kaynak_vals, kaynak_labels);
% Renk ayarla
p(1).FaceColor = c_pv;
p(3).FaceColor = c_wt;
title(sprintf('(b) Üretim Kaynak Payı\nToplam: %.2f kWh/gün', E_PV_gun+E_WT_gun), ...
      'FontSize', 12, 'FontWeight', 'bold');

sgtitle(sprintf('Şekil 8 – Günlük Enerji Özeti | LPSP=%.4f | COE=$%.4f/kWh', ...
        best_LPSP, best_COE), 'FontSize', 13, 'FontWeight', 'bold');

fprintf('\n✓ Tüm grafikler başarıyla oluşturuldu (Şekil 1–8).\n');
fprintf('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

%% =========================================================================
%  FONKSIYON TANIMLARI
% =========================================================================

function [NPC, LPSP, COE] = hesapla_NPC_LPSP(x, PV, WT, BAT, INV, Econ, ...
                                          PWF_OM, G_t, Tamb, V, PLoad, T)
% -------------------------------------------------------------------------
%  x = [N_PV, N_WT, N_bat] için NPC, LPSP ve COE hesaplar.
%
%  COE = (NPC × CRF) / E_yillik    [$/kWh]
%  LPSP = Σ P_deficit(t) / Σ P_Load(t)
%  NPC  = C_cap + C_OM + C_rep
% -------------------------------------------------------------------------

    N_PV = x(1);  N_WT = x(2);  N_bat = x(3);

    % 1. PV Çıkış Gücü 
    T_cell = Tamb + ((PV.NOCT - 20)/800) .* G_t;
    P_PV   = N_PV .* PV.P_rated .* (G_t/PV.G_STC) .* ...
             (1 + PV.alpha_T .* (T_cell - PV.T_STC));
    P_PV   = max(0, P_PV);

    % 2. Rüzgar Türbini Çıkış Gücü 
    P_WT = zeros(1, T);
    for h = 1:T
        v = V(h);
        if v < WT.v_ci || v > WT.v_co
            P_WT(h) = 0;
        elseif v >= WT.v_ci && v < WT.v_r
            P_WT(h) = N_WT * WT.P_rated * ((v - WT.v_ci)/(WT.v_r - WT.v_ci))^3;
        else
            P_WT(h) = N_WT * WT.P_rated;
        end
    end

    % 3. Batarya Simülasyonu 
    E_bat_tot = N_bat * BAT.E_cap;
    SOC       = zeros(1, T+1);
    SOC(1)    = BAT.SOC0;
    P_def     = zeros(1, T);

    for h = 1:T
        P_net = P_PV(h) + P_WT(h) - PLoad(h);
        if P_net >= 0
            dSOC     = (BAT.eta_c * P_net) / E_bat_tot;
            SOC(h+1) = min(BAT.SOC_max, SOC(h) + dSOC);
        else
            avail    = (SOC(h) - BAT.SOC_min) * E_bat_tot * BAT.eta_d;
            need     = abs(P_net);
            if avail >= need
                SOC(h+1) = SOC(h) - need / E_bat_tot;
            else
                P_def(h) = need - avail;
                SOC(h+1) = BAT.SOC_min;
            end
        end
    end

    % 4. LPSP
    LPSP = sum(P_def) / sum(PLoad);

    % 5. NPC
    C_cap = N_PV*PV.C_cap + N_WT*WT.C_cap + N_bat*BAT.C_cap + INV.C_cap;

    C_om_yillik = N_PV*PV.C_om + N_WT*WT.C_om + N_bat*BAT.C_om;
    C_OM  = C_om_yillik * PWF_OM;

    C_rep = 0;
    n_rep_bat = floor(Econ.T_proj / BAT.L);
    for k = 1:(n_rep_bat - 1)
        C_rep = C_rep + N_bat * BAT.C_rep / (1 + Econ.r)^(k * BAT.L);
    end
    n_rep_inv = floor(Econ.T_proj / INV.L);
    for k = 1:(n_rep_inv - 1)
        C_rep = C_rep + INV.C_rep / (1 + Econ.r)^(k * INV.L);
    end

    NPC = C_cap + C_OM + C_rep;

    % 6. COE
    E_karsilanan_gun = sum(PLoad) - sum(P_def);
    E_yillik         = E_karsilanan_gun * 365;
    if E_yillik <= 0
        COE = inf;
    else
        COE = (NPC * Econ.CRF) / E_yillik;
    end
end

% -------------------------------------------------------------------------

function fit = hesapla_fitness(NPC, LPSP, LPSP_max)
% -------------------------------------------------------------------------
%  ABC fitness fonksiyonu — büyük = iyi.
%  Minimizasyon: fit = 1/(1+NPC)
%  Kısıt ihlalinde ağır ceza uygulanır.
% -------------------------------------------------------------------------
    if LPSP <= LPSP_max
        fit = 1 / (1 + NPC);
    else
        ceza = 1e6 * (LPSP - LPSP_max);
        fit  = 1 / (1 + NPC + ceza);
    end
end