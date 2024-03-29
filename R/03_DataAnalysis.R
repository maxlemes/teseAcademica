rm(list = ls())

library(tidyverse) # necessario
library(lubridate) # necessario
library(tidyquant) # necessario
library(PortfolioAnalytics) 

# Escolhendo os ativos --------------------------------------------------------

# carregando os retornos dos ativos
load("data/Best10.rda")
load("data/returns.rda")

# Selecionando o periodo desejado
datas <- format(seq(as.Date("2016-01-01"), as.Date("2022-07-01"), by="months"), 
                format="%Y-%m-%d")


# Selecionando os ativos desejados
tickers <- d10$volHighLow %>% 
  sort()
name <- "volHighLow"

# filtrando os retornos dos ativos
d10_ret <- returns
d10_ret <- d10_ret[,names(d10_ret) %in% tickers]
d10_ret <- d10_ret[,order(names(d10_ret))]


# removendo os dados antigos do diretorio antes de rodar o algoritmo
unlink("../matlab/dRet/*")
unlink("../matlab/dCov/*")
unlink("../matlab/dStdev/*")

for (i in 1:(length(datas)-12)){
    
    # definindo o periodo  ----------------------------------------
    data_ini <- date(datas[i])
    data_fim <- date(datas[i+12])
    
    # Filtrando os retornos no periodo
    R <- d10_ret
    R <- R[index(R) >= data_ini]
    R <- R[index(R) <  data_fim]
    
    # Calculando os retornos
    ret <- colMeans(R)
    
    # Salvando os novos dados
    if (i < 10){
      write.csv(ret, file = paste0("../matlab/dRet/dRet0",i,".csv"), row.names=FALSE)
    }
    else {
      write.csv(ret, file = paste0("../matlab/dRet/dRet",i,".csv"), row.names=FALSE)
    }
    
    # Calculando a matriz de covariancia
    R_cov <- cov(R)
    
    # Salvando os novos dados
    if (i < 10){
      write.csv(R_cov, file = paste0("../matlab/dCov/iCov0",i,".csv"), row.names=FALSE)
    }
    else {
      write.csv(R_cov, file = paste0("../matlab/dCov/iCov",i,".csv"), row.names=FALSE)
    }
    
    # Calculando a Volatilidade
    vol <- StdDev(R)
    
    # Salvando os novos dados
    if (i < 10){
      write.csv(vol, file = paste0("../matlab/dStdev/Stdev0",i,".csv"), row.names=FALSE)
    }
    else {
      write.csv(vol, file = paste0("../matlab/dStdev/Stdev",i,".csv"), row.names=FALSE)
    }
}

# Ir para o MatLab rodar os algoritmos (mainRPP.m e main) e voltar

# montando os rebalanceamentos do RPP
rpp <- list.files(path="data-raw/pesos/rpp/", pattern=".csv")
mvp <- list.files(path="data-raw/pesos/mvp/", pattern=".csv")

df <- as_tibble(tickers) %>%
  rename(Ticker = value)
dt <- df

# Capturando os pesos do Matlab
for (i in 1:(length(datas)-12)){
  p <- read.csv(paste0("data-raw/pesos/rpp/",rpp[i]), header = FALSE)
  q <- read.csv(paste0("data-raw/pesos/mvp/",mvp[i]), header = FALSE)
  
  # organizando em colunas
  p <- pivot_longer(p,1:ncol(p),values_to = "peso")
  q <- pivot_longer(q,1:ncol(q),values_to = "peso")
  
  # arrendondando a soma para 1
  p[,2] <- p[,2]/colSums(p[,2])
  q[,2] <- q[,2]/colSums(q[,2])
  
  df[,ncol(df)+1] <- p[,2]
  colnames(df)[ncol(df)] <- gsub(".csv", "", rpp[i])
  
  dt[,ncol(dt)+1] <- q[,2]
  colnames(dt)[ncol(dt)] <- gsub(".csv", "", mvp[i])
}

# Checando se a soma dos pesos é igual a 1
colSums(df[,-1])
colSums(dt[,-1])


#dg[,(ncol(dg)-2):ncol(dg)] <- dg[,(ncol(dg)-5):(ncol(dg)-3)]


# Criando um xts com a primeira entrada
 # dt <- datas
 # datas <- dt
 #datas <- dt[1:50] # até 2020-01-01
 #datas <- dt[37:length(dt)] # de 2020-01-01 até o fim
 #datas <- dt[37:61]

data_ini <- date(datas[13])
ports_ret <- xts(cbind(MVP=0, RPP=0, IBOV=0), data_ini)

# Calculando o Retorno do portfolio
for (i in 1:(length(datas)-13)){

  # definindo o periodo  ----------------------------------------
  data_fim <- date(datas[i+13])
  
  R <- d10_ret
  R <- R[index(R) > index(ports_ret)[nrow(ports_ret)]]
  R <- R[index(R) < data_fim]
  
  # Minimum Variance Porfolio - MVP
  w <- dt[[1+i]]
  mv <- Return.portfolio(R, 
                         weights = w,
                         rebalance_on = NA, 
                         geometric = TRUE, 
                         wealth.index = FALSE,
                         verbose = FALSE
                         )
  colnames(mv) <- "MVP"
  
  # Risk Parity Portfolio - RPP
  w <- df[[1+i]]
  rp <- Return.portfolio(R, 
                         weights = w,
                         rebalance_on = NA, 
                         geometric = TRUE, 
                         wealth.index = FALSE,
                         verbose = FALSE
  )
  mv$RPP <- rp
  
  # Adding IBOV
  R <- returns[!is.na(returns[,'IBOV']), 'IBOV']
  R <- R[index(R) > index(ports_ret)[nrow(ports_ret)]]
  R <- R[index(R) < data_fim]
  
  ib <- Return.portfolio(R, 
                         rebalance_on = NA, 
                         geometric = TRUE, 
                         wealth.index = FALSE,
                         verbose = FALSE
  )
  
  mv$IBOV <- ib
  
  ports_ret <- rbind(ports_ret, mv)
  
  print(i)
}

ports_ret <- ports_ret[!is.na(ports_ret[,'IBOV']),]
ports <- ports_ret

ports$MVP  <- cumprod(1+ports_ret$MVP)
ports$RPP  <- cumprod(1+ports_ret$RPP)
ports$IBOV <- cumprod(1+ports_ret$IBOV)

ports1 <- ports[index(ports)<="2019-12-30"]

ports2 <- ports[index(ports)>="2019-12-30"]
ports2$MVP  <- ports2$MVP/ports2$MVP[[1]]
ports2$RPP  <- ports2$RPP/ports2$RPP[[1]]
ports2$IBOV <- ports2$IBOV/ports2$IBOV[[1]]


# Plot 
ggplot(ports, aes(x=Index)) +
  geom_line(aes(y=RPP, color = "RPP"), size=1)+
  geom_line(aes(y=MVP, color = "MVP"), size=1)+
  geom_line(aes(y=IBOV, color = "IBOV"), size=1)

head(ports)
tail(ports)
table.AnnualizedReturns(Return.calculate(ports))
table.AnnualizedReturns(Return.calculate(ports1))
table.AnnualizedReturns(Return.calculate(ports2))
# table.CalendarReturns((RPP$MVP))
# table.CalendarReturns((RPP$RPP))
# Salvando os dados
save(ports,  file = "data/ports.rda")
save(ports1, file = "data/ports1.rda")
save(ports2, file = "data/ports2.rda")



# ------ Definindo as contribuiçoes de Risco ---------
for (i in 1:(length(datas)-13)){ #-13

  # definindo o periodo  ----------------------------------------
  data_ini <- date(datas[i+1]) # +1
  data_fim <- date(datas[i+13])      # +13
  
  R <- d10_ret
  R <- R[index(R) >= data_ini]
  R <- R[index(R) < data_fim]
  
  # Calculando a matriz de covariancia
  R_cov <- cov(R)
  
  # definindo os pesos do período 
  pesos <- df[[1+i]] # RPP
  
  # Volatilidade do portfólio
  sigma <- pesos %*% R_cov %*% pesos
  sigma <- sqrt(sigma)
  
  # Risk contribution
  v <- R_cov %*% pesos
  dp <- sqrt(252)*(pesos * v )/sigma[[1]]
  dp <- dp  %>%
    as.data.frame() %>%
    rownames_to_column(var = 'yahoo') %>%
    pivot_longer(cols = -yahoo, names_to = 'group2') %>%
    .[,c(1,3)]
  
  df[,ncol(df)+1] <- dp[,2]/sum(dp[,2])
  
  if (i < 10){
    colnames(df)[ncol(df)] <- paste0("RPP0",i)
  }
  else{
    colnames(df)[ncol(df)] <- paste0("RPP",i)
  }
  
  # ----------------------- MVP ----------------------------------
  
  # definindo os pesos do período 
  # pesos <- rep(1/nrow(df), nrow(df)) # Pesos iguais
  pesos <- dt[[1+i]] # MVP
  
  # Volatilidade do portfólio
  sigma <- pesos %*% R_cov %*% pesos
  sigma <- sqrt(sigma)
  
  # Risk contribution
  v <- R_cov %*% pesos
  dp <- sqrt(252)*(pesos * v )/sigma[[1]]
  dp <- dp  %>%
    as.data.frame() %>%
    rownames_to_column(var = 'yahoo') %>%
    pivot_longer(cols = -yahoo, names_to = 'group2') %>%
    .[,c(1,3)]
  
  dt[,ncol(dt)+1] <- dp[,2]/sum(dp[,2])
  
  if (i < 10){
    colnames(dt)[ncol(dt)] <- paste0("MVP0",i)
  }
  else{
    colnames(dt)[ncol(dt)] <- paste0("MVP",i)
  }
  print(i)
}

# Salvando os dados
save(df, file = "data/RiskContributionsRPP.rda")
save(dt, file = "data/RiskContributionsMVP.rda")
#save(d10_ret, file = "data/RiskContributionsMVP.rda")
