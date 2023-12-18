<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8" autoFlush="true" %>
<html>
<head>
    <title>Java Risk Demo</title>
</head>
<body>
<form action="${pageContext.servletContext.contextPath}/get" method="get">
    <table>
        <tr>
            <td>Bucket Name:</td>
            <td><input name="bucket"></td>
        </tr>
        <tr>
            <td>Object Name:</td>
            <td><input name="object"></td>
        </tr>
    </table>
    <input type="submit"/>
</form>
<hr/>
<%
    response.getWriter().flush();

    if (request.getAttribute("error") != null) {
        out.print(String.valueOf(request.getAttribute("error")));
    }
    if (request.getAttribute("content") != null) {
        out.print(String.valueOf(request.getAttribute("content")));
    }
%>
</body>
</html>
